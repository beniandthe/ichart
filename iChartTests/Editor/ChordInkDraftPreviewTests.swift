#if canImport(UIKit)
import CoreGraphics
import PencilKit
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

    func testDraftStateOrdersPreviewByVisualLanePlacement() {
        let leftMeasureID = UUID()
        let rightMeasureID = UUID()
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: rightMeasureID,
                measureIndex: 0,
                fraction: 0.1,
                bestCandidateText: "Cdim7",
                visualOrder: 0.72
            ),
            draftInput(
                measureID: leftMeasureID,
                measureIndex: 1,
                fraction: 0.9,
                bestCandidateText: "Bb-7",
                visualOrder: 0.55
            )
        ])

        XCTAssertEqual(state.draftChords.compactMap(\.previewText), ["Bb-7", "Cdim7"])
    }

    func testDraftBarlineRecognizerAcceptsTallStraightLaneStrokeAndRejectsSlashStroke() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let verticalStroke = InkStroke(points: [
            InkPoint(x: 150, y: 94, timeOffset: 0),
            InkPoint(x: 151, y: 118, timeOffset: 0.1),
            InkPoint(x: 150, y: 141, timeOffset: 0.2)
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
        XCTAssertEqual(recognition.barlines[0].sourceStrokeIndex, 0)
        XCTAssertEqual(recognition.strokeIndices, [0])
        XCTAssertTrue(recognition.barlines[0].isRenderable)
    }

    func testDraftBarlineRecognizerAcceptsOpenLaneStrokeBeyondRenderedMeasureBox() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let openLaneStroke = InkStroke(points: [
            InkPoint(x: 360, y: 94, timeOffset: 0),
            InkPoint(x: 361, y: 118, timeOffset: 0.1),
            InkPoint(x: 360, y: 141, timeOffset: 0.2)
        ])

        XCTAssertFalse(
            pageLayout.systems[0].measures[0].chordWritingFrame.contains(
                CGPoint(x: 360, y: 118)
            )
        )
        XCTAssertTrue(
            LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout)[0].contains(
                CGPoint(x: 360, y: 118)
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

    func testDraftBarlineRecognizerTargetsOpenMeasureFromContinuationLane() throws {
        var chart = Chart.draft(title: "Continuation Lane", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Lane",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let continuationLane = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout).dropFirst().first
        )
        let stroke = InkStroke(points: [
            InkPoint(x: Double(continuationLane.midX), y: Double(continuationLane.minY + 2), timeOffset: 0),
            InkPoint(x: Double(continuationLane.midX + 1), y: Double(continuationLane.midY), timeOffset: 0.1),
            InkPoint(x: Double(continuationLane.midX), y: Double(continuationLane.maxY - 2), timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [stroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines.first?.measureID, openMeasureID)
        XCTAssertEqual(recognition.barlines.first?.measureIndex, 1)
        XCTAssertEqual(recognition.barlines.first?.fraction ?? 0, 0.5, accuracy: 0.04)
        XCTAssertEqual(recognition.strokeIndices, [0])
    }

    func testChordTargetingUsesContinuationLaneFromActiveScopeLocalCoordinates() throws {
        var chart = Chart.draft(title: "Continuation Chord", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Chord",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let localCenter = CGPoint(
            x: continuationLane.midX - chordRegion.frame.minX,
            y: continuationLane.midY - chordRegion.frame.minY
        )
        let drawing = PKDrawing(strokes: [
            Self.pkStroke(points: [
                CGPoint(x: localCenter.x - 12, y: localCenter.y + 12),
                CGPoint(x: localCenter.x + 12, y: localCenter.y - 12)
            ])
        ])

        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordRegion.frame,
                pageLayout: pageLayout
            )
        )
        let laneLocation = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: drawing,
                chordFrame: chordRegion.frame,
                pageLayout: pageLayout
            )
        )

        XCTAssertEqual(target.measureID, openMeasureID)
        XCTAssertEqual(laneLocation.systemIndex, 1)
        XCTAssertEqual(laneLocation.fraction, 0.5, accuracy: 0.04)
    }

    func testChordBatchTargetingSplitsSameOpenMeasureInkAcrossContinuationLanes() throws {
        var chart = Chart.draft(title: "Continuation Batch", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Batch",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let firstLane = try XCTUnwrap(chordRegion.inputFrames.first)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let firstLocalCenter = CGPoint(
            x: firstLane.midX - chordRegion.frame.minX,
            y: firstLane.midY - chordRegion.frame.minY
        )
        let continuationLocalCenter = CGPoint(
            x: continuationLane.midX - chordRegion.frame.minX,
            y: continuationLane.midY - chordRegion.frame.minY
        )
        let drawing = PKDrawing(strokes: [
            Self.pkStroke(points: [
                CGPoint(x: firstLocalCenter.x - 10, y: firstLocalCenter.y - 10),
                CGPoint(x: firstLocalCenter.x + 10, y: firstLocalCenter.y + 10)
            ]),
            Self.pkStroke(points: [
                CGPoint(x: continuationLocalCenter.x - 10, y: continuationLocalCenter.y - 10),
                CGPoint(x: continuationLocalCenter.x + 10, y: continuationLocalCenter.y + 10)
            ])
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordRegion.frame,
            pageLayout: pageLayout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.map(\.measureID), [openMeasureID, openMeasureID])
        XCTAssertEqual(targets.map { $0.laneLocation?.systemIndex }, [0, 1])
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testDraftBarlineRecognizerRejectsChordLikeVerticalStrokeInsideLane() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let chordStemStroke = InkStroke(points: [
            InkPoint(x: 150, y: 108, timeOffset: 0),
            InkPoint(x: 151, y: 122, timeOffset: 0.1),
            InkPoint(x: 150, y: 136, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [chordStemStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertTrue(recognition.barlines.isEmpty)
        XCTAssertTrue(recognition.strokeIndices.isEmpty)
    }

    func testDraftStateRemovesSelectedBarlineAndPreservesBarlineIDAcrossRecognitionPasses() throws {
        let measureID = UUID()
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.42, sourceStrokeIndex: 2)
        ])

        let stableID = try XCTUnwrap(state.draftBarlines.first?.id)
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.421, sourceStrokeIndex: 2)
        ])

        XCTAssertEqual(state.draftBarlines.first?.id, stableID)
        let removedBarline = try XCTUnwrap(state.removeDraftBarline(id: stableID))
        XCTAssertEqual(removedBarline.sourceStrokeIndex, 2)
        XCTAssertTrue(state.draftBarlines.isEmpty)
    }

    func testDraftBarlineOverlaySelectsThenDeletesSelectedLine() throws {
        let measureID = UUID()
        let barline = draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.5)
        let laneFrame = CGRect(x: 100, y: 80, width: 400, height: 50)
        let lineFrame = ChordDraftBarlineOverlayGeometry.lineFrame(for: barline, in: laneFrame)

        let selectTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            barlines: [barline],
            laneFrameForMeasureID: { _ in laneFrame },
            selectedBarlineID: nil
        )
        XCTAssertEqual(selectTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .select))

        let deleteByLineTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            barlines: [barline],
            laneFrameForMeasureID: { _ in laneFrame },
            selectedBarlineID: barline.id
        )
        XCTAssertEqual(deleteByLineTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .delete))

        let deleteFrame = ChordDraftBarlineOverlayGeometry.controlFrames(for: barline, in: laneFrame).delete
        let deleteByControlTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            barlines: [barline],
            laneFrameForMeasureID: { _ in laneFrame },
            selectedBarlineID: barline.id
        )
        XCTAssertEqual(deleteByControlTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .delete))
    }

    func testDraftBatchRenderCommitsOnlyOnExplicitRender() throws {
        var chart = Chart.draft(title: "Draft Chords", layoutStyle: .simpleChordSheet)
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

    func testDraftBatchRenderUsesDrawnBarlineSpacingForCommittedMeasureWidths() throws {
        var chart = Chart.draft(title: "Drawn Spacing", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Drawn Spacing",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.25),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.75)
        ])
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let sourceLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: sourceLayout).first)

        let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: .drawn)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let measures = try XCTUnwrap(layout.systems.first?.measures)
        let widths = measures.map(\.frame.width)

        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertEqual(widths.count, 3)
        XCTAssertGreaterThan(widths[1], widths[0] * 1.45)
        XCTAssertGreaterThan(widths[1], widths[2] * 1.45)
        XCTAssertEqual(
            measures[0].trailingBarlineFrame.midX,
            sourceLane.minX + sourceLane.width * 0.25,
            accuracy: 10
        )
        XCTAssertEqual(
            measures[1].trailingBarlineFrame.midX,
            sourceLane.minX + sourceLane.width * 0.75,
            accuracy: 10
        )
    }

    func testDraftBarlineAutoCommitPlacesSecondSameLaneBoundaryInCurrentOpenSpan() throws {
        var chart = Chart.draft(title: "Same Lane Sequential", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Same Lane Sequential",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let pageSize = CGSize(width: 900, height: 1400)
        let firstOpenMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let initialLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: initialLayout).first)
        let firstBoundaryX = initialLane.minX + initialLane.width * 0.32

        let firstRenderedIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: firstOpenMeasureID, measureIndex: 1, fraction: 0.32)],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(firstRenderedIDs.count, 1)

        let currentOpenMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let afterFirstLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let currentOpenLayout = try XCTUnwrap(
            afterFirstLayout.systems.first?.measures.first(where: { $0.sourceMeasureID == currentOpenMeasureID })
        )
        let sameSystemLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: afterFirstLayout).first)
        let secondBoundaryX = currentOpenLayout.frame.minX + currentOpenLayout.frame.width * 0.45
        let secondLaneFraction = Double((secondBoundaryX - sameSystemLane.minX) / sameSystemLane.width)

        let secondRenderedIDs = chart.commitChordInkDraftBarlines(
            [
                draftBarline(
                    measureID: currentOpenMeasureID,
                    measureIndex: currentOpenLayout.index,
                    fraction: secondLaneFraction
                )
            ],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(secondRenderedIDs.count, 1)

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let finalMeasures = try XCTUnwrap(finalLayout.systems.first?.measures)

        XCTAssertEqual(finalMeasures.count, 3)
        XCTAssertEqual(finalMeasures[0].trailingBarlineFrame.midX, firstBoundaryX, accuracy: 12)
        XCTAssertEqual(finalMeasures[1].trailingBarlineFrame.midX, secondBoundaryX, accuracy: 12)
    }

    func testDraftBarlineAutoCommitSplitsCommittedSameLaneSpan() throws {
        var chart = Chart.draft(title: "Committed Span Split", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Committed Span Split",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let pageSize = CGSize(width: 900, height: 1400)
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let initialLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: initialLayout).first)
        let firstBoundaryX = initialLane.minX + initialLane.width * 0.55

        let firstRenderedIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.55)],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(firstRenderedIDs.count, 1)

        let committedLeftMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let afterFirstLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let committedLeftLayout = try XCTUnwrap(
            afterFirstLayout.systems.first?.measures.first(where: { $0.sourceMeasureID == committedLeftMeasureID })
        )
        let sameSystemLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: afterFirstLayout).first)
        let secondBoundaryX = committedLeftLayout.frame.minX + committedLeftLayout.frame.width * 0.36
        let secondLaneFraction = Double((secondBoundaryX - sameSystemLane.minX) / sameSystemLane.width)

        let secondRenderedIDs = chart.commitChordInkDraftBarlines(
            [
                draftBarline(
                    measureID: committedLeftMeasureID,
                    measureIndex: committedLeftLayout.index,
                    fraction: secondLaneFraction
                )
            ],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(secondRenderedIDs.count, 1)

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let finalMeasures = try XCTUnwrap(finalLayout.systems.first?.measures)

        XCTAssertEqual(finalMeasures.count, 3)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        XCTAssertEqual(finalMeasures[0].trailingBarlineFrame.midX, secondBoundaryX, accuracy: 12)
        XCTAssertEqual(finalMeasures[1].trailingBarlineFrame.midX, firstBoundaryX, accuracy: 12)
    }

    func testDraftBarlineOnlyCommitPreservesChordInkDrawing() throws {
        var chart = Chart.draft(title: "Auto Barline", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Auto Barline",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("draft-chord-ink".utf8)))

        let renderedBarlineIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.4)],
            layoutPageSize: CGSize(width: 900, height: 1400),
            barlineSpacingMode: .drawn
        )

        XCTAssertEqual(renderedBarlineIDs.count, 1)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .open])
        XCTAssertNotNil(chart.pageHandwrittenChordData)
    }

    func testDraftBatchRenderCanEvenlySpaceDraftBarlineMeasures() throws {
        var chart = Chart.draft(title: "Even Spacing", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Even Spacing",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.25),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.75)
        ])

        let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: .even)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let system = try XCTUnwrap(layout.systems.first)
        let widths = system.measures.map { measure in
            LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                measure,
                in: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            ).frame.width
        }

        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths[0], widths[1], accuracy: 2.1)
        XCTAssertEqual(widths[1], widths[2], accuracy: 2.1)
    }

    func testDraftBatchRenderUsesDraftBarlineSegmentsForOpenLanePlacement() throws {
        var chart = Chart.draft(title: "Segmented Draft", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Segmented Draft",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertEqual(chart.measures.first?.authoringState, .open)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.15,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.15)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.5,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.5)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.85,
                bestCandidateText: "G",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.85)
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.33),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.66)
        ])

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("segmented-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 3)
        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        XCTAssertEqual(chart.measures[0].chordEvents.map { $0.symbol.displayText }, ["C"])
        XCTAssertEqual(chart.measures[1].chordEvents.map { $0.symbol.displayText }, ["F"])
        XCTAssertEqual(chart.measures[2].chordEvents.map { $0.symbol.displayText }, ["G"])
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testDraftBatchRenderPreservesOpenLaneOrderWhenRightSideChordsShareMeasure() throws {
        var chart = Chart.draft(title: "Open Lane Order", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane Order",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.12,
                bestCandidateText: "B-9",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.12)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.9999,
                bestCandidateText: "G7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.72)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.9999,
                bestCandidateText: "A7sus",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.86)
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)
        let renderedChords = chart.measures[0].chordEvents
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let renderedLayouts = try XCTUnwrap(layout.systems.first?.measures.first?.chordLayouts)

        XCTAssertEqual(result.renderedChordCount, 3)
        XCTAssertEqual(renderedChords.map { $0.symbol.displayText }, ["B-9", "G7", "A7sus"])
        XCTAssertEqual(renderedChords.map { $0.manualLaneFraction ?? -1 }, [0.12, 0.72, 0.86])
        XCTAssertEqual(renderedLayouts.map(\.text), ["B-9", "G7", "A7sus"])
        XCTAssertLessThan(renderedLayouts[0].frame.minX, renderedLayouts[1].frame.minX)
        XCTAssertLessThan(renderedLayouts[1].frame.minX, renderedLayouts[2].frame.minX)
    }

    func testDraftBatchRenderMaterializesContinuationLaneForLowerLineChord() throws {
        var chart = Chart.draft(title: "Lower Lane Chord", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Lower Lane Chord",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.64,
                bestCandidateText: "D△7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 2, fraction: 0.64),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)
        let renderedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let renderedChordSystemIndex = try XCTUnwrap(
            renderedLayout.systems.firstIndex { system in
                system.measures.contains { measure in
                    measure.chordLayouts.contains { $0.text == "D△7" }
                }
            }
        )

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(chart.systems.count, 3)
        XCTAssertEqual(renderedChordSystemIndex, 2)
        XCTAssertTrue(chart.systems[0].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertTrue(chart.systems[1].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertEqual(chart.systems[2].measures.first?.chordEvents.map { $0.symbol.displayText }, ["D△7"])
        let renderedLane = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: renderedLayout.systems[2],
                paperFrame: renderedLayout.paperFrame
            )
        )
        let renderedChordLayout = try XCTUnwrap(renderedLayout.systems[2].measures.first?.chordLayouts.first)
        XCTAssertEqual(
            renderedChordLayout.frame.minX,
            renderedLane.minX + renderedLane.width * 0.64,
            accuracy: 8
        )
    }

    func testDraftBatchRenderKeepsDraftChordsOnSeparateContinuationLines() throws {
        var chart = Chart.draft(title: "Separate Lanes", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Separate Lanes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.28,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.28),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.72,
                bestCandidateText: "G7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 3, fraction: 0.72),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 2)
        XCTAssertEqual(chart.systems.count, 4)
        XCTAssertEqual(chart.systems[1].measures.first?.chordEvents.map { $0.symbol.displayText }, ["C"])
        XCTAssertEqual(chart.systems[3].measures.first?.chordEvents.map { $0.symbol.displayText }, ["G7"])
        XCTAssertTrue(chart.systems[0].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertTrue(chart.systems[2].measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testDraftBatchRenderResolvesLanePlacementAgainstCurrentMeasureGeometry() throws {
        var chart = Chart.blank(title: "Lane Insert", measureCount: 2, layoutStyle: .simpleChordSheet)
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        _ = try XCTUnwrap(appendRecognizedChord("C", to: firstMeasureID, in: &chart))
        _ = try XCTUnwrap(appendRecognizedChord("G", to: secondMeasureID, in: &chart))

        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let secondMeasureLayout = try XCTUnwrap(
            layout.systems.first?.measures.first(where: { $0.sourceMeasureID == secondMeasureID })
        )
        let laneFraction = Double((secondMeasureLayout.chordBandFrame.midX - laneFrame.minX) / laneFrame.width)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: firstMeasureID,
                measureIndex: 1,
                fraction: 0.1,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: laneFraction),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertFalse(chart.measures[0].chordEvents.map { $0.symbol.displayText }.contains("F"))
        XCTAssertEqual(chart.measures[1].chordEvents.map { $0.symbol.displayText }, ["G", "F"])
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
        visualOrder: Double? = nil,
        laneLocation: ChordInkDraftLaneLocation? = nil,
        layoutPageSize: CGSize? = nil,
        drawingData: Data = Data("ink".utf8)
    ) -> ChordInkDraftInput {
        ChordInkDraftInput(
            measureID: measureID,
            measureIndex: measureIndex,
            targetFraction: fraction,
            visualOrder: visualOrder,
            laneLocation: laneLocation,
            layoutPageSize: layoutPageSize,
            drawingData: drawingData,
            candidateTexts: [bestCandidateText],
            bestCandidateText: bestCandidateText,
            confidence: 4.2,
            strokeCount: 2
        )
    }

    private func draftBarline(
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        sourceStrokeIndex: Int? = nil
    ) -> DraftBarline {
        DraftBarline(
            measureID: measureID,
            measureIndex: measureIndex,
            fraction: fraction,
            sourceStrokeIndex: sourceStrokeIndex,
            metrics: DraftBarlineGestureMetrics(
                height: 54,
                width: 2,
                angleDegreesFromVertical: 1,
                straightness: 0.98,
                laneCoverage: 0.9
            )
        )
    }

    private func appendRecognizedChord(_ text: String, to measureID: UUID, in chart: inout Chart) -> UUID? {
        guard let match = ChordRecognitionCompendium.match(text) else {
            return nil
        }

        return chart.appendRecognizedChordEvent(
            match.symbol,
            rawInput: text,
            to: measureID,
            atFraction: 0.1
        )
    }

    private static func pageLayout(measureID: UUID) -> LeadSheetPageLayout {
        let measure = LeadSheetMeasureLayout(
            id: measureID,
            sourceMeasureID: measureID,
            chordInkTargetMeasureID: measureID,
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

    private static func pkStroke(points: [CGPoint]) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.05,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        )
    }
}
#endif

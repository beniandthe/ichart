#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkIndependentStructuralRenderTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 500)

    func testRenderingAnEndingKeepsTheRhythmWritingLaneAndCanvasFrameSteady() throws {
        var chart = makeChart(.rhythmSectionSheet)
        let original = try geometry(chart)
        let originalRows = LeadSheetActiveInkScope.chordWritingRegion(for: original.layout)
        let firstID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: firstID, endMeasureID: firstID,
            displayText: "1.", endStyle: .closed))
        let rendered = try geometry(chart)
        XCTAssertEqual(LeadSheetActiveInkScope.chordWritingRegion(for: rendered.layout), originalRows)
        XCTAssertEqual(rendered.system.measures.map(\.staffFrame), original.system.measures.map(\.staffFrame))
        XCTAssertLessThan(rendered.lane.maxY, try XCTUnwrap(rendered.system.measures.first).staffFrame.minY)
    }

    func testLegacyEndingDraftMigratesWithoutChangingItsPaperPositionAndReopensWithoutAnotherMigration() throws {
        for width in [CGFloat(932), CGFloat(1_180)] {
            var chart = makeChart(.rhythmSectionSheet)
            let firstID = try XCTUnwrap(chart.measures.first?.id)
            _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: firstID, endMeasureID: firstID,
                displayText: "1.", endStyle: .closed))
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: width, height: 1_400),
                includesChordInkContinuationLanes: true)
            let legacy = LeadSheetActiveInkScope.legacyChordWritingRegion(for: layout)
            let current = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
            XCTAssertNotEqual(legacy.frame.size, current.frame.size)
            let oldLane = try XCTUnwrap(legacy.inputFrames.first)
            let top = oldLane.minY - legacy.frame.minY + 2
            let bottom = oldLane.maxY - legacy.frame.minY - 2
            let old = normalized([
                stroke([CGPoint(x: 35, y: top), CGPoint(x: 45, y: top + 2)], seed: 200),
                stroke([CGPoint(x: 55, y: bottom - 2), CGPoint(x: 65, y: bottom)], seed: 201)
            ])
            let savedSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: legacy.frame.size))
            _ = chart.setPageHandwrittenChordDrawing(old.dataRepresentation(), coordinateSpace: savedSpace)
            let scope = LeadSheetActiveInkScope.chords(frame: current.frame, inputFrames: current.inputFrames)
            let migrated = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.migratingLegacyChordScopeDrawing(
                from: chart.pageHandwrittenChordData, sourceCoordinateSpace: savedSpace,
                activeInkScope: scope, pageLayout: layout))
            let oldPaper = old.transformed(using: CGAffineTransform(translationX: legacy.frame.minX, y: legacy.frame.minY))
            let newPaper = migrated.transformed(using: CGAffineTransform(translationX: current.frame.minX, y: current.frame.minY))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: oldPaper, current: newPaper))
            XCTAssertEqual(migrated.strokes[0].path.map(\.location), old.strokes[0].path.map(\.location),
                "The migration translates the stroke transform without stretching its path")
            let canvasBounds = CGRect(origin: .zero, size: current.frame.size)
            for stroke in migrated.strokes {
                XCTAssertTrue(canvasBounds.contains(stroke.renderBounds), "Legacy edge ink must remain visible inside the canvas")
                let paperBounds = stroke.renderBounds.offsetBy(dx: current.frame.minX, dy: current.frame.minY)
                XCTAssertTrue(current.inputFrames.contains { $0.contains(paperBounds) },
                    "The migrated legacy edge must remain a usable input area")
            }
            let calibratedLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: layout.systems[0], paperFrame: layout.paperFrame(for: layout.systems[0])))
            XCTAssertLessThanOrEqual(calibratedLane.height, current.inputFrames[0].height)
            let currentSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: current.frame.size))
            _ = chart.setPageHandwrittenChordDrawing(migrated.dataRepresentation(), coordinateSpace: currentSpace)
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertNil(LeadSheetPersistentInkCoordinateSpacePolicy.migratingLegacyChordScopeDrawing(
                from: reopened.pageHandwrittenChordData, sourceCoordinateSpace: reopened.pageHandwrittenChordCoordinateSpace,
                activeInkScope: scope, pageLayout: layout))
            let reloaded = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
                from: reopened.pageHandwrittenChordData, sourceCoordinateSpace: reopened.pageHandwrittenChordCoordinateSpace,
                targetCoordinateSpace: currentSpace))
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: migrated, current: reloaded))
            let arbitrarySpace = PersistentInkCoordinateSpace(width: savedSpace.width, height: savedSpace.height + 0.5)
            XCTAssertNil(LeadSheetPersistentInkCoordinateSpacePolicy.migratingLegacyChordScopeDrawing(
                from: old.dataRepresentation(), sourceCoordinateSpace: arbitrarySpace,
                activeInkScope: scope, pageLayout: layout), "Only the exact reconstructed legacy size authorizes migration")
        }
    }

    func testLegacyLowerLaneBarlineKeepsItsAcceptedGeometryAfterMigration() throws {
        var chart = makeChart(.rhythmSectionSheet)
        let firstID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: firstID, endMeasureID: firstID,
            displayText: "1.", endStyle: .closed))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.last)
        let legacy = LeadSheetActiveInkScope.legacyChordWritingRegion(for: layout)
        let current = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.legacyChordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let x = measure.staffFrame.midX - legacy.frame.minX
        let top = lane.minY + lane.height * 0.05 - legacy.frame.minY
        let bottom = lane.maxY - lane.height * 0.05 - legacy.frame.minY
        let old = normalized([stroke([CGPoint(x: x, y: top), CGPoint(x: x, y: bottom)], seed: 210)])
        let before = ChordDraftBarlineRecognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: old),
            chordFrame: legacy.frame, pageLayout: layout)
        XCTAssertEqual(before.barlines.count, 1, "The source fits the legacy lane under the original shape thresholds")
        let scope = LeadSheetActiveInkScope.chords(frame: current.frame, inputFrames: current.inputFrames)
        let migrated = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.migratingLegacyChordScopeDrawing(
            from: old.dataRepresentation(), sourceCoordinateSpace: PersistentInkCoordinateSpace(size: legacy.frame.size),
            activeInkScope: scope, pageLayout: layout))
        _ = chart.setPageHandwrittenChordDrawing(migrated.dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: current.frame.size))
        let preparation = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: inputAt,
            requestedDelay: 0, drawingData: migrated.dataRepresentation(), chordFrame: current.frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        XCTAssertEqual(preparation.barlines.count, 1)
        XCTAssertEqual(preparation.recognitionStrokeCount, 0, "A migrated accepted barline must not enter chord OCR")
        XCTAssertEqual(preparation.barlines.first?.metrics, before.barlines.first?.metrics)
    }

    func testIndependentDividerRendersWhileUnreadChordStaysAtItsOriginalMeasureAndLocation() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [true, false] {
                var chart = makeChart(style)
                let ids = chart.measures.map(\.id)
                let geometry = try self.geometry(chart)
                let first = try XCTUnwrap(geometry.system.measures.first { $0.sourceMeasureID == ids[0] })
                let last = try XCTUnwrap(geometry.system.measures.first { $0.sourceMeasureID == ids[2] })
                let line = barline(at: first.staffFrame.midX, kind: .single, geometry: geometry, seed: 1)
                let unknown = unreadChord(at: last.staffFrame.midX, geometry: geometry, seed: 20)
                let source = normalized(line + unknown)
                let state = try prepare(source, in: &chart, geometry: geometry)
                XCTAssertEqual(state.draftBarlines.count, 1)
                XCTAssertEqual(state.draftChords.count, 1)
                XCTAssertEqual(state.draftChords.first?.measureID, ids[2])
                XCTAssertFalse(state.draftChords[0].isRenderable)

                let outcome = try render(chart, state: state, source: source, geometry: geometry, manual: manual)
                XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
                XCTAssertEqual(outcome.result.renderedChordCount, 0)
                XCTAssertEqual(outcome.chart.measures.count, chart.measures.count + 1)
                let retained = try XCTUnwrap(outcome.retainedDraft)
                XCTAssertEqual(retained.state.draftChords.map(\.id), state.draftChords.map(\.id))
                XCTAssertEqual(retained.state.draftChords.first?.measureID, ids[2])
                XCTAssertEqual(retained.state.draftChords.first?.measureIndex, 4)
                XCTAssertTrue(retained.state.draftBarlines.isEmpty)
                try assertRetained(normalized(unknown), outcome: outcome)
                let destination = try self.geometry(outcome.chart)
                let after = try XCTUnwrap(destination.system.measures.first { $0.sourceMeasureID == ids[2] })
                XCTAssertEqual(after.staffFrame, last.staffFrame)
                XCTAssertEqual(after.chordWritingFrame, last.chordWritingFrame)
            }
        }
    }

    func testCompleteRepeatRendersWhileUnreviewedEndingStaysAvailable() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [true, false] {
                var chart = makeChart(style)
                let geometry = try self.geometry(chart)
                let first = try XCTUnwrap(geometry.system.measures.first)
                let last = try XCTUnwrap(geometry.system.measures.last)
                let repeatStrokes = barline(at: first.staffFrame.minX + 1, kind: .repeatStart,
                    geometry: geometry, seed: 30)
                    + barline(at: first.staffFrame.maxX - 1, kind: .repeatEnd, geometry: geometry, seed: 40)
                let endingStrokes = ending(over: last, geometry: geometry, seed: 50)
                let source = normalized(repeatStrokes + endingStrokes)
                let state = try prepare(source, in: &chart, geometry: geometry)
                XCTAssertEqual(state.draftBarlines.map(\.kind), [.repeatStart, .repeatEnd])
                XCTAssertEqual(state.draftEndings.count, 1)
                XCTAssertFalse(state.draftEndings[0].isReviewed)
                XCTAssertTrue(state.draftChords.isEmpty)

                let outcome = try render(chart, state: state, source: source, geometry: geometry, manual: manual)
                XCTAssertEqual(outcome.result.renderedBarlineCount, 2)
                XCTAssertEqual(outcome.chart.measures.map(\.id), chart.measures.map(\.id))
                let span = try XCTUnwrap(outcome.chart.roadmapObjects.first { $0.type == .repeatSpan })
                let archive = try PKDrawing(data: XCTUnwrap(span.sourceInkData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: normalized(repeatStrokes), current: archive))
                let retained = try XCTUnwrap(outcome.retainedDraft)
                XCTAssertEqual(retained.state.draftEndings.map(\.id), state.draftEndings.map(\.id))
                XCTAssertFalse(retained.state.draftEndings[0].isReviewed)
                XCTAssertTrue(retained.state.draftBarlines.isEmpty)
                try assertRetained(normalized(endingStrokes), outcome: outcome)
            }
        }
    }

    func testReviewedEndingRendersWhileUnrelatedUnreadChordRemains() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [true, false] {
                var chart = makeChart(style)
                let geometry = try self.geometry(chart)
                let first = try XCTUnwrap(geometry.system.measures.first)
                let last = try XCTUnwrap(geometry.system.measures.last)
                let bracket = ending(over: first, geometry: geometry, seed: 60)
                let unknown = unreadChord(at: last.staffFrame.midX, geometry: geometry, seed: 70)
                let source = normalized(bracket + unknown)
                let state = try prepare(source, in: &chart, geometry: geometry)
                XCTAssertEqual(state.draftEndings.count, 1)
                XCTAssertEqual(state.draftChords.count, 1)
                let review = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
                let approved = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: review,
                    chart: chart, currentState: state, label: "1.", endStyle: .closed, measureRange: 1...1))

                let outcome = try render(chart, state: approved, source: source, geometry: geometry, manual: manual)
                XCTAssertEqual(outcome.result.renderedEndingCount, 1)
                XCTAssertEqual(outcome.result.renderedChordCount, 0)
                let mark = try XCTUnwrap(outcome.chart.roadmapObjects.first { $0.type.isEnding })
                let archive = try PKDrawing(data: XCTUnwrap(mark.sourceInkData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                    expected: normalized(bracket), current: archive))
                XCTAssertEqual(mark.startMeasureID, first.sourceMeasureID)
                XCTAssertEqual(mark.endMeasureID, first.sourceMeasureID)
                try assertRetained(normalized(unknown), outcome: outcome)
            }
        }
    }

    func testIndependentChordDoesNotDiscardAnApprovalForAnEndingThatCannotBeDuplicated() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for manual in [true, false] {
                var chart = makeChart(style)
                let middleID = chart.measures[1].id
                _ = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: middleID,
                    endMeasureID: middleID, displayText: "1.", endStyle: .closed))
                let geometry = try self.geometry(chart)
                let middle = try XCTUnwrap(geometry.system.measures.dropFirst().first)
                let last = try XCTUnwrap(geometry.system.measures.last)
                let bracket = ending(over: middle, geometry: geometry, seed: 90)
                let chordStrokes = unreadChord(at: last.staffFrame.midX, geometry: geometry, seed: 100)
                let source = normalized(bracket + chordStrokes)
                var state = try prepare(source, in: &chart, geometry: geometry)
                XCTAssertEqual(state.draftChords.count, 1)
                state.draftChords[0].bestCandidateText = "C"
                state.draftChords[0].candidateTexts = ["C"]
                let review = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
                let approved = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: review,
                    chart: chart, currentState: state, label: "1.", endStyle: .closed, measureRange: 2...2))

                let outcome = try render(chart, state: approved, source: source, geometry: geometry, manual: manual)
                XCTAssertEqual(outcome.result.renderedChordCount, 1)
                XCTAssertEqual(outcome.result.renderedEndingCount, 0)
                let retained = try XCTUnwrap(outcome.retainedDraft)
                let ending = try XCTUnwrap(retained.state.draftEndings.first)
                XCTAssertTrue(ending.isReviewed, "Unrelated chord progress must not require a second ending approval")
                XCTAssertEqual(ending.reviewedSourceInkData, approved.draftEndings[0].reviewedSourceInkData)
                XCTAssertEqual(ending.reviewedMeasureRange, 2...2)
                XCTAssertTrue(ending.reviewedRangeContext?.matches(chart: outcome.chart, state: retained.state) == true)
                try assertRetained(normalized(bracket), outcome: outcome)
            }
        }
    }

    func testUnrepresentedRawInkDoesNotHoldAnIndependentChordOrDivider() throws {
        for manual in [true, false] {
            for rendersDivider in [true, false] {
                var chart = makeChart(.rhythmSectionSheet)
                let geometry = try self.geometry(chart)
                let first = try XCTUnwrap(geometry.system.measures.first)
                let last = try XCTUnwrap(geometry.system.measures.last)
                let selected = rendersDivider
                    ? barline(at: first.staffFrame.midX, kind: .single, geometry: geometry, seed: 110)
                    : unreadChord(at: first.staffFrame.midX, geometry: geometry, seed: 110)
                let unknown = unreadChord(at: last.staffFrame.midX, geometry: geometry, seed: 120)
                let source = normalized(selected + unknown)
                var state = try prepare(source, in: &chart, geometry: geometry)
                if rendersDivider {
                    state.draftChords = []
                } else {
                    XCTAssertEqual(state.draftChords.count, 2)
                    state.draftChords = Array(state.draftChords.prefix(1))
                    state.draftChords[0].bestCandidateText = "C"
                    state.draftChords[0].candidateTexts = ["C"]
                }
                XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasValidRepresentedCoverage(chart: chart, state: state))
                let outcome = try render(chart, state: state, source: source, geometry: geometry, manual: manual)
                XCTAssertEqual(outcome.result.renderedBarlineCount, rendersDivider ? 1 : 0)
                XCTAssertEqual(outcome.result.renderedChordCount, rendersDivider ? 0 : 1)
                let retained = try XCTUnwrap(outcome.retainedDraft)
                XCTAssertTrue(retained.state.isEmpty)
                let raw = normalized(unknown)
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: raw, current: retained.drawing))
                let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(outcome.chart))
                let saved = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: raw, current: saved))
                if !rendersDivider {
                    let event = try XCTUnwrap(reopened.measures.flatMap(\.chordEvents).first)
                    let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
                    XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                        expected: source, current: PKDrawing(strokes: archive.strokes + retained.drawing.strokes)))
                }
            }
        }
    }

    func testConflictingClosingRepeatsCannotRenderAnArbitrarySubset() throws {
        var chart = makeChart(.rhythmSectionSheet)
        let ids = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: ids[1]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let firstSystem = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == ids[0] } })
        let secondSystem = try XCTUnwrap(layout.systems.first { $0.measures.contains { $0.sourceMeasureID == ids[1] } })
        let firstLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: firstSystem, paperFrame: layout.paperFrame(for: firstSystem)))
        let secondLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: secondSystem, paperFrame: layout.paperFrame(for: secondSystem)))
        let first = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID == ids[0] })
        let second = try XCTUnwrap(secondSystem.measures.first { $0.sourceMeasureID == ids[1] })
        let firstGeometry = Geometry(layout: layout, system: firstSystem, frame: frame, lane: firstLane)
        let secondGeometry = Geometry(layout: layout, system: secondSystem, frame: frame, lane: secondLane)
        let source = normalized(barline(at: first.staffFrame.maxX - 1, kind: .repeatEnd, geometry: firstGeometry, seed: 220)
            + barline(at: second.staffFrame.minX + 1, kind: .repeatEnd, geometry: secondGeometry, seed: 230))
        let state = try prepare(source, in: &chart, geometry: firstGeometry)
        XCTAssertEqual(state.draftBarlines.map(\.kind), [.repeatEnd, .repeatEnd])
        let original = chart
        let manual = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            sourcePageLayout: layout, sourceChordFrame: frame)
        XCTAssertFalse(manual.canConsumeSource)
        XCTAssertEqual(manual.chart, original)
        let automatic = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
            currentDrawing: source, coordinateSpace: PersistentInkCoordinateSpace(size: frame.size),
            now: inputAt.addingTimeInterval(10), lastInputAt: inputAt, isUsingTool: false,
            sourcePageLayout: layout, sourceChordFrame: frame)
        XCTAssertNil(automatic.outcome)
    }

    private struct Geometry {
        let layout: LeadSheetPageLayout
        let system: LeadSheetSystemLayout
        let frame: CGRect
        let lane: CGRect
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Independent structural progress", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 3)
        return chart
    }

    private func geometry(_ chart: Chart) throws -> Geometry {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Geometry(layout: layout, system: system,
            frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
    }

    private func prepare(_ source: PKDrawing, in chart: inout Chart, geometry: Geometry) throws -> ChordPreviewState {
        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(),
            coordinateSpace: PersistentInkCoordinateSpace(size: geometry.frame.size))
        let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(),
            scheduledAt: inputAt, requestedDelay: 0, drawingData: source.dataRepresentation(),
            chordFrame: geometry.frame, pageLayout: geometry.layout, flow: .draftPreview,
            options: .live, layoutStyle: chart.layoutStyle))
        var state = ChordPreviewState(draftBarlines: prepared.barlines,
            draftEndings: prepared.endings, layoutPageSize: pageSize)
        if case .ready(let requests, _) = prepared.outcome {
            let inputs = requests.map { request in
                ChordInkDraftInput(measureID: request.target.measureID, measureIndex: (chart.measures.firstIndex { $0.id == request.target.measureID } ?? 0) + 1,
                    targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                    laneLocation: request.laneLocation, layoutPageSize: pageSize, drawingData: request.drawingData,
                    candidateTexts: [], bestCandidateText: nil, confidence: 0, strokeCount: request.strokes.count,
                    targetLifecycle: request.collectingTargetLifecycle.advanced(to: .stable))
            }
            state.replaceDraftChords(with: inputs)
        }
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        return state
    }

    private func render(_ chart: Chart, state: ChordPreviewState, source: PKDrawing,
        geometry: Geometry, manual: Bool) throws -> ChordInkDraftRenderCoordinator.Outcome {
        let coordinateSpace = PersistentInkCoordinateSpace(size: geometry.frame.size)
        let outcome: ChordInkDraftRenderCoordinator.Outcome
        if manual {
            outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                currentDrawing: source, coordinateSpace: coordinateSpace,
                sourcePageLayout: geometry.layout, sourceChordFrame: geometry.frame)
        } else {
            let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                currentDrawing: source, coordinateSpace: coordinateSpace,
                now: inputAt.addingTimeInterval(10), lastInputAt: inputAt, isUsingTool: false,
                sourcePageLayout: geometry.layout, sourceChordFrame: geometry.frame)
            outcome = ChordInkDraftRenderCoordinator.explicitOutcome(try XCTUnwrap(attempt.outcome,
                "Independent structural notation must progress. Feedback: \(attempt.feedback)"))
        }
        XCTAssertTrue(outcome.canConsumeSource)
        return outcome
    }

    private func assertRetained(_ source: PKDrawing, outcome: ChordInkDraftRenderCoordinator.Outcome) throws {
        let retained = try XCTUnwrap(outcome.retainedDraft)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: retained.drawing))
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(outcome.chart))
        let saved = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: saved))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: reopened, state: retained.state))
        XCTAssertEqual(reopened, outcome.chart)
    }

    private func barline(at x: CGFloat, kind: DraftBarlineKind, geometry: Geometry, seed: Int) -> [PKStroke] {
        let height = geometry.lane.height * 0.84
        let center = CGPoint(x: x - geometry.frame.minX, y: geometry.lane.midY - geometry.frame.minY)
        var strokes = [stroke([CGPoint(x: center.x, y: center.y - height / 2),
            CGPoint(x: center.x, y: center.y + height / 2)], seed: seed)]
        for side in [-1.0, 1.0] where side < 0 ? kind.endsRepeat : kind.startsRepeat {
            for vertical in [-1.0, 1.0] {
                strokes.append(stroke([CGPoint(x: center.x + CGFloat(side) * height * 0.20,
                    y: center.y + CGFloat(vertical) * height * 0.18)], seed: seed + strokes.count, width: 1.4))
            }
        }
        return strokes
    }

    private func unreadChord(at x: CGFloat, geometry: Geometry, seed: Int) -> [PKStroke] {
        let center = CGPoint(x: x - geometry.frame.minX, y: geometry.lane.midY - geometry.frame.minY)
        return [stroke([CGPoint(x: center.x - 7, y: center.y - 5), CGPoint(x: center.x + 7, y: center.y + 5),
            CGPoint(x: center.x - 7, y: center.y + 5), CGPoint(x: center.x + 7, y: center.y - 5)], seed: seed)]
    }

    private func ending(over measure: LeadSheetMeasureLayout, geometry: Geometry, seed: Int) -> [PKStroke] {
        let left = measure.staffFrame.minX + 3 - geometry.frame.minX
        let right = measure.staffFrame.maxX - 3 - geometry.frame.minX
        let top = geometry.lane.minY + geometry.lane.height * 0.12 - geometry.frame.minY
        return [stroke([CGPoint(x: left, y: top + geometry.lane.height * 0.20), CGPoint(x: left, y: top)], seed: seed),
            stroke([CGPoint(x: left, y: top), CGPoint(x: right, y: top)], seed: seed + 1)]
    }

    private func normalized(_ strokes: [PKStroke]) -> PKDrawing {
        LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
    }

    private func stroke(_ points: [CGPoint], seed: Int, width: CGFloat = 2.5) -> PKStroke {
        let path = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                size: CGSize(width: width, height: width), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }
}
#endif

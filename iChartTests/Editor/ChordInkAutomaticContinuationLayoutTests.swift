#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// An open Simple Chart measure fills its row. Committing ink on the virtual
/// lane below must not compress that already-rendered row into a beat slot.
@MainActor
final class ChordInkAutomaticContinuationLayoutTests: XCTestCase {
    private let pageSize = CGSize(width: 932, height: 1_200)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)

    func testSequentialAutomaticContinuationPreservesEarlierRowsThroughThirdRowAndReopen() throws {
        var chart = makeChart()
        try renderFirstRow(into: &chart, mode: .automatic)
        let firstID = try XCTUnwrap(chart.measures.first?.id)
        let first = try snapshot(firstID, in: chart)
        XCTAssertGreaterThan(first.measureFrame.width, 600,
            "The fixture must begin with the ordinary full-width open measure")
        XCTAssertTrue(chart.measures[0].chordEvents.allSatisfy { $0.manualVisualLaneFraction != nil })

        let secondInput = try input(chart, rowIndex: 1, fraction: 0.18, text: "D", seed: 10)
        XCTAssertEqual(secondInput.draft.laneLocation?.systemIndex, 1)
        XCTAssertEqual(secondInput.draft.measureID, firstID,
            "The ordinary virtual continuation still targets the existing open measure before materialization")
        assertUnchanged(first, in: chart)
        let second = try commit(secondInput, to: chart, mode: .automatic)
        chart = second.chart
        XCTAssertEqual(chart.systems.count, 2)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures[0].authoringState, .committed)
        XCTAssertEqual(chart.measures[1].authoringState, .open)
        assertUnchanged(first, in: chart)
        try assertNewSource(secondInput.drawing, result: second.result, in: chart)
        let secondID = chart.measures[1].id
        let secondSnapshot = try snapshot(secondID, in: chart)

        let thirdInput = try input(chart, rowIndex: 2, fraction: 0.24, text: "E", seed: 11)
        XCTAssertEqual(thirdInput.draft.laneLocation?.systemIndex, 2)
        XCTAssertEqual(thirdInput.draft.measureID, secondID)
        assertUnchanged(first, in: chart)
        assertUnchanged(secondSnapshot, in: chart)
        let third = try commit(thirdInput, to: chart, mode: .automatic)
        chart = third.chart
        XCTAssertEqual(chart.systems.count, 3)
        XCTAssertEqual(chart.measures.count, 3)
        assertUnchanged(first, in: chart)
        assertUnchanged(secondSnapshot, in: chart)
        try assertNewSource(thirdInput.drawing, result: third.result, in: chart)
        XCTAssertNil(chart.pageHandwrittenChordData)

        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(chart))
        XCTAssertEqual(reopened.measures.map(\.id), chart.measures.map(\.id))
        assertUnchanged(first, in: reopened)
        assertUnchanged(secondSnapshot, in: reopened)
        XCTAssertEqual(reopened.measures.map(\.chordEvents), chart.measures.map(\.chordEvents),
            "Event identity, order, musical placement, visual intent and original source bytes must survive reopen")
    }

    func testExplicitReviewOfAutomaticContinuationPreservesTheCompletedTopRow() throws {
        var chart = makeChart()
        try renderFirstRow(into: &chart, mode: .automatic)
        let first = try snapshot(chart.measures[0].id, in: chart)
        let next = try input(chart, rowIndex: 1, fraction: 0.32, text: "Bb", seed: 12, trusted: false)
        XCTAssertFalse(ChordInkAutomaticRenderPolicy.isTrusted(next.draft))
        let result = try commit(next, to: chart, mode: .reviewedAutomatic)
        XCTAssertEqual(result.chart.systems.count, 2)
        assertUnchanged(first, in: result.chart)
        try assertNewSource(next.drawing, result: result.result, in: result.chart)
        let event = try XCTUnwrap(result.chart.measures[1].chordEvents.first)
        XCTAssertEqual(event.rawInput, "Bb")
        XCTAssertNotNil(event.manualVisualLaneFraction)
    }

    func testContinuationPreservesCommittedMeasureAndActualOpenRemainderInTheSameRow() throws {
        var chart = makeChart(startingMeasureCount: 2)
        let firstID = chart.measures[0].id
        let openID = chart.measures[1].id
        XCTAssertEqual(chart.measures[0].authoringState, .committed)
        XCTAssertEqual(chart.measures[1].authoringState, .open)
        let firstInput = try input(chart, rowIndex: 0, fraction: 0.05, text: "F", seed: 20)
        XCTAssertEqual(firstInput.draft.measureID, firstID)
        chart = try commit(firstInput, to: chart, mode: .automatic).chart
        for (index, value) in [(0.35, "G"), (0.6, "B"), (0.82, "C")].enumerated() {
            let source = try input(chart, rowIndex: 0, fraction: value.0, text: value.1, seed: 21 + index)
            XCTAssertEqual(source.draft.measureID, openID)
            chart = try commit(source, to: chart, mode: .automatic).chart
        }
        let first = try snapshot(firstID, in: chart)
        let remainder = try snapshot(openID, in: chart)
        XCTAssertGreaterThan(remainder.measureFrame.width, first.measureFrame.width * 2,
            "The final open measure must occupy the actual remaining row width")
        let next = try input(chart, rowIndex: 1, fraction: 0.18, text: "D", seed: 25)
        XCTAssertEqual(next.draft.measureID, openID)
        let result = try commit(next, to: chart, mode: .automatic)
        XCTAssertEqual(result.chart.systems.count, 2)
        XCTAssertEqual(result.chart.systems[0].measures.map(\.id), [firstID, openID])
        assertUnchanged(first, in: result.chart)
        assertUnchanged(remainder, in: result.chart)
        XCTAssertNil(result.chart.measure(id: firstID)?.manualLayoutWidth,
            "A neighboring committed measure must not acquire the open measure's width intent")
        try assertNewSource(next.drawing, result: result.result, in: result.chart)
    }

    func testOneAutomaticBatchMaterializesTwoVirtualRowsWithoutContractingTheirSourceGeometry() throws {
        var chart = makeChart()
        try renderFirstRow(into: &chart, mode: .automatic)
        let first = try snapshot(chart.measures[0].id, in: chart)
        let second = try input(chart, rowIndex: 1, fraction: 0.18, text: "D", seed: 30)
        let third = try input(chart, rowIndex: 2, fraction: 0.32, text: "E", seed: 31)
        XCTAssertEqual(second.draft.laneLocation?.systemIndex, 1)
        XCTAssertEqual(third.draft.laneLocation?.systemIndex, 2)
        let secondGhost = try XCTUnwrap(second.layout.systems.first { $0.index == 1 }?.measures.first)
        let thirdGhost = try XCTUnwrap(third.layout.systems.first { $0.index == 2 }?.measures.first)
        let drawing = PKDrawing(strokes: second.drawing.strokes + third.drawing.strokes)
        let state = ChordPreviewState(draftChords: [second.draft, third.draft], layoutPageSize: pageSize)
        let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
            currentDrawing: drawing, coordinateSpace: PersistentInkCoordinateSpace(size: second.sourceFrame.size),
            now: inputAt.addingTimeInterval(2), lastInputAt: inputAt, isUsingTool: false,
            allowsImmediateSpatialCompletion: true, sourcePageLayout: second.layout, sourceChordFrame: second.sourceFrame)
        let result = try XCTUnwrap(attempt.outcome, "Both complete virtual-lane targets must commit: \(attempt.feedback)")
        XCTAssertEqual(result.result.renderedChordCount, 2)
        XCTAssertEqual(result.chart.systems.count, 3)
        XCTAssertEqual(result.chart.measures.count, 3)
        assertUnchanged(first, in: result.chart)
        let newSecond = try snapshot(result.chart.measures[1].id, in: result.chart)
        let newThird = try snapshot(result.chart.measures[2].id, in: result.chart)
        XCTAssertFalse(second.layout.systems.flatMap(\.measures).contains {
            $0.sourceMeasureID == newSecond.measureID
        }, "The second newly created open ID must be absent from the original source layout")
        XCTAssertEqual(newSecond.measureFrame, secondGhost.frame,
            "Closing a measure created in the same batch must use its original virtual-row geometry")
        XCTAssertEqual(newSecond.chordBandFrame, secondGhost.chordBandFrame)
        XCTAssertEqual(newThird.measureFrame, thirdGhost.frame)
        XCTAssertEqual(newThird.chordBandFrame, thirdGhost.chordBandFrame)
        let renderedIDs = Set(result.result.renderedChordIDs)
        let events = result.chart.measures.flatMap(\.chordEvents).filter { renderedIDs.contains($0.id) }
        for expected in [second.drawing, third.drawing] {
            let matches = try events.filter { event in
                let stored = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
                return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: stored)
            }
            XCTAssertEqual(matches.count, 1, "Each virtual-row source must belong to exactly one new chord")
        }
        XCTAssertTrue(result.drawing.strokes.isEmpty)
        XCTAssertNil(result.chart.pageHandwrittenChordData)
        XCTAssertEqual(result.chart.measures[1].authoringState, .committed)
        XCTAssertEqual(result.chart.measures[2].authoringState, .open)
    }

    func testManualContinuationKeepsItsExistingWidthAndVisualPlacementPolicy() throws {
        var chart = makeChart()
        try renderFirstRow(into: &chart, mode: .manual)
        let firstID = chart.measures[0].id
        let originalEvents = chart.measures[0].chordEvents
        XCTAssertNil(chart.measures[0].manualLayoutWidth)
        XCTAssertTrue(originalEvents.allSatisfy { $0.manualVisualLaneFraction == nil })
        let next = try input(chart, rowIndex: 1, fraction: 0.32, text: "D", seed: 13)
        let result = try commit(next, to: chart, mode: .manual)
        let first = try XCTUnwrap(result.chart.measure(id: firstID))
        XCTAssertNil(first.manualLayoutWidth,
            "The automatic continuation correction must not introduce a width override into manual rendering")
        XCTAssertEqual(first.chordEvents, originalEvents)
        XCTAssertTrue(result.chart.measures.flatMap(\.chordEvents).allSatisfy { $0.manualVisualLaneFraction == nil })
        try assertNewSource(next.drawing, result: result.result, in: result.chart)
    }

    func testCustomOpenMeasureWidthIsPreservedAndUnsafeContractionRefusesContinuation() throws {
        for contracts in [false, true] {
            var chart = makeChart()
            let initial = pageLayout(chart)
            let system = try XCTUnwrap(initial.systems.first)
            let sourceMeasure = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == chart.measures[0].id })
            let fittingWidth = LeadSheetPageLayoutEngine.simpleChordSheetManualLayoutWidthForTargetRowWidth(
                sourceMeasure.frame.width, chart: chart, maxSystemWidth: initial.paperFrame(for: system).width - 68)
            let customWidth = fittingWidth * (contracts ? 0.5 : 1)
            _ = chart.setMeasureManualLayoutWidth(customWidth, for: chart.measures[0].id)
            try renderFirstRow(into: &chart, mode: .automatic)
            let before = try snapshot(chart.measures[0].id, in: chart)
            let original = chart
            let next = try input(chart, rowIndex: 1, fraction: 0.2, text: "D", seed: 14)
            let bytes = next.drawing.dataRepresentation()
            let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: next.state,
                currentDrawing: next.drawing, coordinateSpace: PersistentInkCoordinateSpace(size: next.sourceFrame.size),
                now: inputAt.addingTimeInterval(2), lastInputAt: inputAt, isUsingTool: false,
                allowsImmediateSpatialCompletion: true, sourcePageLayout: next.layout, sourceChordFrame: next.sourceFrame)
            if contracts {
                XCTAssertNil(attempt.outcome, "Existing custom width must not be overwritten to authorize a collapsing row")
                XCTAssertEqual(chart, original)
                XCTAssertEqual(next.drawing.dataRepresentation(), bytes)
                assertUnchanged(before, in: chart)
            } else {
                let result = try XCTUnwrap(attempt.outcome)
                assertUnchanged(before, in: result.chart)
                XCTAssertEqual(try XCTUnwrap(result.chart.measure(id: before.measureID)?.manualLayoutWidth),
                    Double(customWidth), accuracy: 0.001)
            }
        }
    }

    func testOptionalCapturedSingletonFillRowRestoresOpenRowGeometryWithoutChangingMusicOrInk() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let fixture = ProcessInfo.processInfo.environment["ICHART_CONTINUATION_LIBRARY"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent(".build/notation-preservation-fixtures/Library/Application Support/iChart/library-state.json")
        guard FileManager.default.fileExists(atPath: fixture.path) else {
            throw XCTSkip("Optional current local continuation fixture is not present")
        }
        guard let chartID = ProcessInfo.processInfo.environment["ICHART_CONTINUATION_CHART_ID"].flatMap(UUID.init(uuidString:)),
              let targetMeasureID = ProcessInfo.processInfo.environment["ICHART_CONTINUATION_MEASURE_ID"].flatMap(UUID.init(uuidString:)) else {
            throw XCTSkip("Optional local replay requires explicit chart and measure identifiers")
        }
        let bytes = try Data(contentsOf: fixture)
        let snapshot = try XCTUnwrap(try FileChartRepository(url: fixture).loadSnapshot())
        let matches = snapshot.charts.filter { $0.id == chartID }
        XCTAssertEqual(matches.count, 1)
        let original = try XCTUnwrap(matches.first)
        let systemIndex = try XCTUnwrap(original.systems.indices.first { index in
            original.systems[index].measures.contains { $0.id == targetMeasureID }
        })
        let measureIndex = try XCTUnwrap(original.systems[systemIndex].measures.indices.first {
            original.systems[systemIndex].measures[$0].id == targetMeasureID
        })
        let measureID = original.systems[systemIndex].measures[measureIndex].id
        XCTAssertEqual(original.systems[systemIndex].measures.count, 1)
        XCTAssertEqual(original.systems[systemIndex].measures[measureIndex].authoringState, .committed)
        XCTAssertNil(original.systems[systemIndex].measures[measureIndex].manualLayoutWidth)
        let before = try self.snapshot(measureID, in: original)
        var openReference = original
        openReference.systems[systemIndex].measures[measureIndex].authoringState = .open
        let expected = try self.snapshot(measureID, in: openReference)
        let sourceLayout = pageLayout(original)
        let sourceSystem = try XCTUnwrap(sourceLayout.systems.first { $0.id == original.systems[systemIndex].id })
        let widths = LeadSheetSimpleChordRowEqualizationPolicy.manualLayoutWidths(
            for: sourceSystem, in: sourceLayout, chart: original)
        let derivedWidth = try XCTUnwrap(widths[measureID])
        XCTAssertEqual(widths.count, 1)
        var repaired = original
        _ = repaired.setMeasureManualLayoutWidth(derivedWidth, for: measureID)
        assertUnchanged(expected, in: repaired)
        XCTAssertGreaterThan(expected.measureFrame.width, before.measureFrame.width * 3.5)

        var allowedOnly = repaired
        allowedOnly.updatedAt = original.updatedAt
        allowedOnly.systems[systemIndex].measures[measureIndex].manualLayoutWidth = nil
        XCTAssertEqual(allowedOnly, original,
            "The explicit Fill Row action may change only its measure width and chart updatedAt")
        XCTAssertEqual(repaired.measures.map(\.chordEvents), original.measures.map(\.chordEvents),
            "Existing musical timing, visual fractions, spelling and every source archive remain exact")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = directory.appendingPathComponent("repaired-chart.json")
        try ChartPersistenceCoders.encoder.encode(repaired).write(to: saved, options: .atomic)
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: Data(contentsOf: saved))
        assertUnchanged(expected, in: reopened)
        XCTAssertEqual(reopened.measures.map(\.chordEvents), original.measures.map(\.chordEvents))
        let restored = try self.snapshot(measureID, in: reopened)
        let expectedOrder = expected.naturalFrames.sorted {
            $0.value.minX == $1.value.minX ? $0.key.uuidString < $1.key.uuidString : $0.value.minX < $1.value.minX
        }.map(\.key)
        let restoredOrder = restored.naturalFrames.sorted {
            $0.value.minX == $1.value.minX ? $0.key.uuidString < $1.key.uuidString : $0.value.minX < $1.value.minX
        }.map(\.key)
        XCTAssertEqual(restoredOrder, expectedOrder)
        let report = XCTAttachment(string: "Captured singleton Fill Row model replay.\nBefore measure=\(before.measureFrame), band=\(before.chordBandFrame)\nRestored measure=\(restored.measureFrame), band=\(restored.chordBandFrame)\nDerived stored width=\(derivedWidth)\nGlyph order matches the open-row reference: \(restoredOrder)\nAll existing chord objects and source archives are exact. This is not a claim about the earlier six-chord layout before its seventh chord was added.")
        report.name = "Private captured singleton Fill Row geometry and preservation"
        report.lifetime = .keepAlways
        add(report)
        XCTAssertEqual(try Data(contentsOf: fixture), bytes)
    }

    private enum Mode { case automatic, reviewedAutomatic, manual }
    private struct Input {
        let drawing: PKDrawing
        let draft: ChordInkDraft
        let layout: LeadSheetPageLayout
        let sourceFrame: CGRect
        var state: ChordPreviewState { .init(draftChords: [draft], layoutPageSize: layout.pageBounds.size) }
    }
    private struct Commit {
        let chart: Chart
        let result: ChordInkDraftBatchRenderResult
    }
    private struct RowSnapshot {
        let measureID: UUID
        let measureFrame: CGRect
        let staffFrame: CGRect
        let chordBandFrame: CGRect
        let writableFrame: CGRect
        let glyphFrames: [UUID: CGRect]
        let naturalFrames: [UUID: CGRect]
        let events: [ChordEvent]
    }

    private func makeChart(startingMeasureCount: Int = 1) -> Chart {
        var chart = Chart.draft(title: "Automatic continuation geometry", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: startingMeasureCount)
        return chart
    }

    private func renderFirstRow(into chart: inout Chart, mode: Mode) throws {
        let texts = ["F", "G", "B", "C"]
        let fractions = [0.05, 0.15, 0.4, 0.55]
        for index in texts.indices {
            let source = try input(chart, rowIndex: 0, fraction: fractions[index], text: texts[index], seed: index + 1)
            XCTAssertEqual(source.draft.laneLocation?.systemIndex, 0)
            chart = try commit(source, to: chart, mode: mode).chart
        }
        XCTAssertEqual(chart.systems.count, 1)
        XCTAssertEqual(chart.measures.count, 1)
        XCTAssertEqual(chart.measures[0].authoringState, .open)
        XCTAssertEqual(chart.measures[0].chordEvents.map(\.rawInput), ["F", "G", "B", "C"])
    }

    private func input(_ chart: Chart, rowIndex: Int, fraction: Double, text: String,
        seed: Int, trusted: Bool = true) throws -> Input {
        let layout = pageLayout(chart)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let system = try XCTUnwrap(layout.systems.first { $0.index == rowIndex })
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        let origin = CGPoint(x: lane.minX + lane.width * CGFloat(fraction) - region.frame.minX,
            y: lane.midY - region.frame.minY)
        let points = [CGPoint(x: origin.x, y: origin.y + 14), CGPoint(x: origin.x, y: origin.y - 14),
            CGPoint(x: origin.x + 18, y: origin.y - 14), CGPoint(x: origin.x + 18, y: origin.y + 14)]
            .enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        let stroke = PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points,
                creationDate: inputAt.addingTimeInterval(Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
        let drawing = PKDrawing(strokes: [stroke])
        let target = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.target(for: drawing,
            chordFrame: region.frame, pageLayout: layout))
        let location = try XCTUnwrap(LeadSheetChordInkRecognitionTargeting.laneLocation(for: drawing,
            chordFrame: region.frame, pageLayout: layout))
        let measure = try XCTUnwrap(chart.measure(id: target.measureID))
        let decision = ChordInkRecognitionDecision(action: trusted ? .trusted : .confirm,
            acceptedText: trusted ? text : nil, reason: "Frozen continuation test read",
            isCloseRace: false, competingCandidateText: nil, confidenceGap: nil)
        var input = ChordInkDraftInput(measureID: target.measureID, measureIndex: measure.index,
            targetFraction: target.fraction, visualOrder: location.visualOrder, laneLocation: location,
            layoutPageSize: pageSize, drawingData: drawing.dataRepresentation(), candidateTexts: [text],
            bestCandidateText: text, confidence: trusted ? 4.5 : 0, strokeCount: 1,
            recognitionDecision: decision)
        input.targetLifecycle = .init(generationID: UUID(), anchor: input.anchor,
            ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)), stage: .frozen)
        return Input(drawing: drawing, draft: ChordInkDraft(input: input), layout: layout, sourceFrame: region.frame)
    }

    private func commit(_ input: Input, to chart: Chart, mode: Mode) throws -> Commit {
        let space = PersistentInkCoordinateSpace(size: input.sourceFrame.size)
        if mode == .manual {
            let prepared = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: input.state,
                currentDrawing: input.drawing, coordinateSpace: space)
            XCTAssertTrue(prepared.canConsumeSource)
            return Commit(chart: prepared.chart, result: prepared.result)
        }
        let attempt: ChordInkDraftRenderCoordinator.AutomaticAttempt
        if mode == .reviewedAutomatic {
            let batch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: input.state))
            let reviewed = try XCTUnwrap(ChordInkDraftReviewPolicy.reviewedState(from: input.state,
                batch: batch, candidateTextByDraftID: [input.draft.id: input.draft.previewText ?? ""]))
            attempt = ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(chart: chart,
                state: reviewed, currentDrawing: input.drawing, coordinateSpace: space, isUsingTool: false,
                sourcePageLayout: input.layout, sourceChordFrame: input.sourceFrame)
        } else {
            attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: input.state,
                currentDrawing: input.drawing, coordinateSpace: space, now: inputAt.addingTimeInterval(2),
                lastInputAt: inputAt, isUsingTool: false, allowsImmediateSpatialCompletion: true,
                sourcePageLayout: input.layout, sourceChordFrame: input.sourceFrame)
        }
        let outcome = try XCTUnwrap(attempt.outcome, "The complete trusted/reviewed continuation must commit, feedback=\(attempt.feedback)")
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        return Commit(chart: outcome.chart, result: outcome.result)
    }

    private func pageLayout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize, includesChordInkContinuationLanes: true)
    }

    private func snapshot(_ measureID: UUID, in chart: Chart) throws -> RowSnapshot {
        let measure = try XCTUnwrap(chart.measure(id: measureID))
        let layout = try XCTUnwrap(pageLayout(chart).systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        return RowSnapshot(measureID: measureID, measureFrame: layout.frame, staffFrame: layout.staffFrame,
            chordBandFrame: layout.chordBandFrame, writableFrame: layout.writableFrame,
            glyphFrames: Dictionary(uniqueKeysWithValues: layout.chordLayouts.map { ($0.id, $0.frame) }),
            naturalFrames: Dictionary(uniqueKeysWithValues: layout.chordLayouts.map { ($0.id, $0.naturalFrame) }),
            events: measure.chordEvents)
    }

    private func assertUnchanged(_ before: RowSnapshot, in chart: Chart,
        file: StaticString = #filePath, line: UInt = #line) {
        do {
            let after = try snapshot(before.measureID, in: chart)
            XCTAssertEqual(after.measureFrame, before.measureFrame, "Completed measure geometry changed", file: file, line: line)
            XCTAssertEqual(after.staffFrame, before.staffFrame, file: file, line: line)
            XCTAssertEqual(after.chordBandFrame, before.chordBandFrame, file: file, line: line)
            XCTAssertEqual(after.writableFrame, before.writableFrame, file: file, line: line)
            XCTAssertEqual(after.glyphFrames, before.glyphFrames, "Previously rendered glyphs moved or compressed", file: file, line: line)
            XCTAssertEqual(after.naturalFrames, before.naturalFrames, file: file, line: line)
            XCTAssertEqual(after.events, before.events, "Existing event IDs, order, timing, visual intent or source bytes changed", file: file, line: line)
        } catch {
            XCTFail("The earlier measure must remain available: \(error)", file: file, line: line)
        }
    }

    private func assertNewSource(_ source: PKDrawing, result: ChordInkDraftBatchRenderResult, in chart: Chart) throws {
        XCTAssertEqual(result.renderedChordCount, 1)
        let event = try XCTUnwrap(chart.measures.flatMap(\.chordEvents).first { result.renderedChordIDs.contains($0.id) })
        let stored = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: stored))
        XCTAssertNil(chart.pageHandwrittenChordData)
    }
}
#endif

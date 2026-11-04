#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Bounded synthetic reader controls and native review/coordinator integration.
/// These cases do not represent a fresh physical Pencil accuracy measurement.
@MainActor
final class DocketCrossStyleRecoveryTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)
    private let inputAt = Date(timeIntervalSinceReferenceDate: 100)
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testFAndEReaderControlsRenderThroughBothStylesAndRenderModes() throws {
        for text in ["F", "F7", "F△7", "E"] {
            for reversesBars in [false, true] {
                let strokes = rootAndSuffix(text, reversesBars: reversesBars)
                if text == "F△7" {
                    XCTAssertTrue(InkSplitMajorTriangleGeometry.matches(strokes[3], strokes[4]),
                        "The synthetic suffix must satisfy the existing sampled-triangle fixture contract")
                }
                let recognition = ChordInkMaximumTrustRecognizer().recognize(strokes: strokes)
                XCTAssertEqual(recognition.match?.displayText, text,
                    "Synthetic \(text), reversed bars: \(reversesBars)")
                guard recognition.match?.displayText == text else { continue }

                for style in styles {
                    for manual in [true, false] {
                        var chart = makeChart(style)
                        let measureID = chart.measures[0].id
                        let layout = pageLayout(chart)
                        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
                        let measure = try XCTUnwrap(layout.systems.flatMap(\.measures)
                            .first { $0.sourceMeasureID == measureID })
                        let source = drawing(strokes,
                            x: measure.chordBandFrame.minX - frame.minX + 35,
                            y: measure.chordWritingFrame.minY - frame.minY + 12)
                        let coordinateSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: frame.size))
                        _ = chart.setPageHandwrittenChordDrawing(source.dataRepresentation(), coordinateSpace: coordinateSpace)
                        let draft = input(chart: chart, drawing: source, result: recognition, text: text)
                        let state = ChordPreviewState(draftChords: [ChordInkDraft(input: draft)], layoutPageSize: pageSize)

                        let rendered = try render(chart, state: state, source: source,
                            coordinateSpace: coordinateSpace, manual: manual, reviewed: false)
                        let saved = try reopen(rendered.chart)
                        XCTAssertEqual(saved.layoutStyle, style)
                        XCTAssertEqual(saved.measures.map(\.id), chart.measures.map(\.id))
                        XCTAssertNil(saved.pageHandwrittenChordData)
                        let events = saved.measures.flatMap(\.chordEvents)
                        XCTAssertEqual(events.count, 1)
                        let event = try XCTUnwrap(events.first)
                        XCTAssertEqual(event.symbol.displayText, text)
                        XCTAssertEqual(rendered.result.renderedChordIDs, [event.id])
                        assertSameInk(source, try PKDrawing(data: XCTUnwrap(event.sourceInkData)))
                        XCTAssertNil(state.draftChords.first?.selectedText,
                            "A reader control must not silently become a user correction")
                    }
                }
            }
        }
    }

    func testExpandedNoReadRecoversOnceInSimpleManual() async throws {
        try await assertExpandedNoReadRecovery(style: .simpleChordSheet, manual: true)
    }

    func testExpandedNoReadRecoversOnceInSimpleAutomatic() async throws {
        try await assertExpandedNoReadRecovery(style: .simpleChordSheet, manual: false)
    }

    func testExpandedNoReadRecoversOnceInRhythmManual() async throws {
        try await assertExpandedNoReadRecovery(style: .rhythmSectionSheet, manual: true)
    }

    func testExpandedNoReadRecoversOnceInRhythmAutomatic() async throws {
        try await assertExpandedNoReadRecovery(style: .rhythmSectionSheet, manual: false)
    }

    private func assertExpandedNoReadRecovery(style: ChartLayoutStyle, manual: Bool) async throws {
        var chart = makeChart(style)
        let targetID = chart.measures[0].id
        let neighborID = chart.measures[1].id
        let neighborSource = drawing(rootAndSuffix("E", reversesBars: false), x: 350, y: 30)
        _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("E7"),
            rawInput: "E7", to: neighborID, atFraction: 0.1,
            sourceInkData: neighborSource.dataRepresentation()))
        let neighborBefore = try XCTUnwrap(chart.measure(id: neighborID))
        let layout = pageLayout(chart)
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let target = try XCTUnwrap(layout.systems.flatMap(\.measures)
            .first { $0.sourceMeasureID == targetID })
        let x = target.chordBandFrame.minX - frame.minX + 35
        let y = target.chordWritingFrame.minY - frame.minY + 12
        let initial = drawing([
            InkStroke(points: points([(0, 0), (0, 42)])),
            InkStroke(points: points([(0, 1), (31, 21), (1, 42)]))
        ], x: x, y: y)
        let detail = drawing([InkStroke(points: points([(11, 11), (22, 31)]))], x: x, y: y)
        let expanded = PKDrawing(strokes: initial.strokes + detail.strokes)
        let coordinateSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: frame.size))
        let staff = drawing([InkStroke(points: points([(0, 0), (15, 12)]))], x: 40, y: 130)
        _ = chart.setPageHandwrittenNotationDrawing(staff.dataRepresentation(), coordinateSpace: coordinateSpace)
        _ = chart.setPageHandwrittenChordDrawing(expanded.dataRepresentation(), coordinateSpace: coordinateSpace)

        var state = ChordPreviewState(layoutPageSize: pageSize)
        let earlierRead = ChordInkRecognitionResult(rawCandidates: ["F7"], glyphCandidates: [],
            match: ChordRecognitionCompendium.match("F7"), confidence: 0.7)
        state.replaceDraftChords(with: [input(chart: chart, drawing: initial, result: earlierRead, text: "F7")])
        let originalRowID = try XCTUnwrap(state.draftChords.first?.id)
        let noRead = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        state.replaceDraftChords(with: [input(chart: chart, drawing: expanded, result: noRead, text: nil)])

        XCTAssertEqual(state.draftChords.count, 1, "Expanded source replaces its old row instead of claiming those strokes twice")
        XCTAssertEqual(state.draftChords.first?.id, originalRowID)
        XCTAssertNil(state.draftChords.first?.previewText)
        XCTAssertFalse(try XCTUnwrap(state.draftChords.first).requiresSeparatedChordInk)
        let firstBatch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: state))
        XCTAssertEqual(firstBatch.confirmations.count, 1)
        let row = try XCTUnwrap(firstBatch.confirmations.first)
        XCTAssertTrue(row.requiresDirectEntry)
        assertSameInk(expanded, try PKDrawing(data: row.drawingData))

        // Exercise the actual native field and Back to Writing callback. The
        // returned draft is then supplied to the normal sheet restoration API.
        let retained = try await editAndReturnToWriting(firstBatch, text: " Fmaj7 ")
        XCTAssertEqual(retained, [row.id: " Fmaj7 "])
        var current = state
        replaceGuess(in: &current, with: "F7")
        let reopenedBatch = try XCTUnwrap(ChordInkDraftReviewPolicy.batch(for: current))
        let submitted = try await restoreAndSubmit(reopenedBatch, retained: retained)
        XCTAssertEqual(submitted, [row.id: "Fmaj7"])

        // A late reader guess for precisely the same owned source cannot
        // replace supported text explicitly submitted through this field.
        replaceGuess(in: &current, with: "E7")
        let reviewed = try ChordInkDraftReviewPolicy.validation(from: current, batch: reopenedBatch,
            candidateTextByDraftID: submitted).get()
        XCTAssertEqual(reviewed.draftChords.map(\.selectedText), ["Fmaj7"])
        XCTAssertEqual(reviewed.draftChords.first?.recognitionResult?.match?.displayText, "E7",
            "The correction and the late recognition evidence remain distinct")
        let rendered = try render(chart, state: reviewed, source: expanded,
            coordinateSpace: coordinateSpace, manual: manual, reviewed: true)
        XCTAssertEqual(rendered.result.renderedChordCount, 1)
        XCTAssertTrue(rendered.result.unresolvedDraftIDs.isEmpty)

        let saved = try reopen(rendered.chart)
        XCTAssertEqual(saved.id, chart.id)
        XCTAssertEqual(saved.layoutStyle, style)
        XCTAssertEqual(saved.measures.map(\.id), chart.measures.map(\.id))
        XCTAssertEqual(saved.measure(id: neighborID), neighborBefore)
        XCTAssertEqual(saved.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
        XCTAssertEqual(saved.pageHandwrittenNotationCoordinateSpace, chart.pageHandwrittenNotationCoordinateSpace)
        XCTAssertNil(saved.pageHandwrittenChordData)
        XCTAssertNil(saved.pageHandwrittenChordCoordinateSpace)
        let events = try XCTUnwrap(saved.measure(id: targetID)).chordEvents
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.symbol.displayText, "F△7")
        XCTAssertEqual(event.rawInput, "Fmaj7")
        let source = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
        XCTAssertEqual(source.strokes.count, 3)
        assertSameInk(expanded, source)
        XCTAssertEqual(rendered.result.renderedChordIDs, [event.id])
    }

    private func editAndReturnToWriting(_ batch: PendingChordInkBatchConfirmation,
        text: String) async throws -> [UUID: String] {
        var edits: [UUID: String] = [:]
        var didReturn = false
        var accepted = false
        let root = ChordInkBatchConfirmationSheetView(batch: batch,
            onAcceptAll: { _ in accepted = true }, onClearAndRewrite: {},
            onBackToInk: { didReturn = true }, onEditedTextsChanged: { edits = $0 })
        let mounted = await mountSheet(root)
        defer { mounted.window.isHidden = true; mounted.window.rootViewController = nil }
        let fields = descendants(mounted.host.view).compactMap { $0 as? IChartTypedUITextField }
            .filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 1)
        let field = try XCTUnwrap(fields.first)
        XCTAssertEqual(field.text, "")
        field.text = text
        field.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        try button("Back to Writing", in: mounted.host.view).sendActions(for: .touchUpInside)
        XCTAssertTrue(didReturn)
        XCTAssertFalse(accepted)
        XCTAssertEqual(field.text, text)
        return edits
    }

    private func restoreAndSubmit(_ batch: PendingChordInkBatchConfirmation,
        retained: [UUID: String]) async throws -> [UUID: String] {
        var accepted: [UUID: String]?
        let root = ChordInkBatchConfirmationSheetView(batch: batch,
            onAcceptAll: { accepted = $0 }, onClearAndRewrite: {},
            initialEditedTextsByID: retained)
        let mounted = await mountSheet(root)
        defer { mounted.window.isHidden = true; mounted.window.rootViewController = nil }
        let fields = descendants(mounted.host.view).compactMap { $0 as? IChartTypedUITextField }
            .filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 1)
        let field = try XCTUnwrap(fields.first)
        XCTAssertEqual(field.text, " Fmaj7 ")
        let render = try button(batch.actionTitle, in: mounted.host.view)
        XCTAssertTrue(render.isEnabled)
        render.sendActions(for: .touchUpInside)
        return try XCTUnwrap(accepted)
    }

    private func mountSheet(_ view: ChordInkBatchConfirmationSheetView) async -> (
        window: UIWindow, host: UIHostingController<ChordInkBatchConfirmationSheetView>
    ) {
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        try? await Task.sleep(nanoseconds: 100_000_000)
        return (window, host)
    }

    private func button(_ label: String, in view: UIView) throws -> PencilOnlyUIButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? PencilOnlyUIButton }
            .first { $0.accessibilityLabel == label })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func replaceGuess(in state: inout ChordPreviewState, with text: String) {
        let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: 0.2)
        state.draftChords[0].candidateTexts = [text]
        state.draftChords[0].bestCandidateText = text
        state.draftChords[0].confidence = result.confidence
        state.draftChords[0].recognitionResult = result
        state.draftChords[0].primaryDecision = ChordInkRecognitionPolicy.decision(for: result)
        state.draftChords[0].recognitionDecision = ChordInkRecognitionPolicy.decision(for: result)
        state.draftChords[0].targetLifecycle?.generationID = UUID()
    }

    private func render(_ chart: Chart, state: ChordPreviewState, source: PKDrawing,
        coordinateSpace: PersistentInkCoordinateSpace, manual: Bool, reviewed: Bool
    ) throws -> (chart: Chart, result: ChordInkDraftBatchRenderResult) {
        let original = chart
        let sourceLayout = pageLayout(chart)
        let sourceFrame = LeadSheetActiveInkScope.chordWritingFrame(for: sourceLayout)
        if manual {
            let outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                currentDrawing: source, coordinateSpace: coordinateSpace,
                sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
            XCTAssertTrue(outcome.canConsumeSource)
            XCTAssertNil(outcome.retainedDraft)
            XCTAssertEqual(chart, original)
            return (outcome.chart, outcome.result)
        }
        let attempt: ChordInkDraftRenderCoordinator.AutomaticAttempt
        if reviewed {
            attempt = ChordInkDraftRenderCoordinator.prepareReviewedAutomaticAttempt(chart: chart,
                state: state, currentDrawing: source, coordinateSpace: coordinateSpace,
                isUsingTool: false, sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
        } else {
            attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart,
                state: state, currentDrawing: source, coordinateSpace: coordinateSpace,
                now: inputAt.addingTimeInterval(4), lastInputAt: inputAt, isUsingTool: false,
                sourcePageLayout: sourceLayout, sourceChordFrame: sourceFrame)
        }
        let outcome = try XCTUnwrap(attempt.outcome)
        XCTAssertTrue(outcome.drawing.strokes.isEmpty)
        XCTAssertTrue(outcome.remainingState.isEmpty)
        XCTAssertEqual(outcome.consumedDraftIDs, Set(state.draftChords.map(\.id)))
        XCTAssertEqual(chart, original)
        return (outcome.chart, outcome.result)
    }

    private func input(chart: Chart, drawing: PKDrawing, result: ChordInkRecognitionResult,
        text: String?) -> ChordInkDraftInput {
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        var input = ChordInkDraftInput(measureID: chart.measures[0].id, measureIndex: 0,
            targetFraction: 0.18, layoutPageSize: pageSize, drawingData: drawing.dataRepresentation(),
            candidateTexts: text.map { [$0] } ?? [], bestCandidateText: text,
            confidence: result.confidence, strokeCount: drawing.strokes.count,
            recognitionResult: result, primaryDecision: decision, recognitionDecision: decision)
        input.targetLifecycle = .init(generationID: UUID(), anchor: input.anchor,
            ownership: .init(preparedStrokes: PencilKitInkAdapter.inkStrokes(from: drawing)), stage: .frozen)
        return input
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Docket cross-style recovery", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 2)
        return chart
    }

    private func pageLayout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        try repository.saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        XCTAssertEqual(snapshot.selectedChartID, chart.id)
        return try XCTUnwrap(snapshot.charts.first)
    }

    private func assertSameInk(_ expected: PKDrawing, _ actual: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.strokes.count, expected.strokes.count, file: file, line: line)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: actual),
            file: file, line: line)
    }

    private func points(_ pairs: [(Double, Double)]) -> [InkPoint] {
        pairs.enumerated().map { index, point in
            InkPoint(x: point.0, y: point.1, timeOffset: Double(index) * 0.05)
        }
    }

    private func rootAndSuffix(_ text: String, reversesBars: Bool) -> [InkStroke] {
        let top = [(10.0, 12.0), (42.0, 12.0)]
        let middle = [(10.0, 35.0), (34.0, 35.0)]
        let stem = text == "E" ? [(10.0, 12.0), (10.0, 60.0), (31.0, 60.0)] : [(10.0, 12.0), (10.0, 60.0)]
        var strokes = [InkStroke(points: points(stem))]
        strokes += [top, middle].map { InkStroke(points: points(reversesBars ? Array($0.reversed()) : $0)) }
        if text == "F7" {
            strokes.append(InkStroke(points: points([(62, 12), (85, 12), (67, 44)])))
        } else if text == "F△7" {
            // A split triangle's existing glyph heuristic requires three
            // samples on the left leg and eight on the leg-plus-base path.
            // Keep the same geometry, with representative path sampling.
            strokes += [InkStroke(points: points([(60, 32), (66, 22), (72, 12)])),
                InkStroke(points: points([(72, 12), (75, 17), (78, 22), (81, 27),
                    (84, 32), (78, 32), (72, 32), (66, 32), (60, 32)])),
                InkStroke(points: points([(94, 12), (117, 12), (99, 44)]))]
        }
        return strokes
    }

    private func drawing(_ strokes: [InkStroke], x: CGFloat, y: CGFloat) -> PKDrawing {
        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        return LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes.enumerated().map { index, stroke in
            let path = PKStrokePath(controlPoints: stroke.points.enumerated().map { pointIndex, point in
                PKStrokePoint(location: CGPoint(x: x + CGFloat(point.x - bounds.minX),
                    y: y + CGFloat(point.y - bounds.minY)),
                    timeOffset: Double(pointIndex) * 0.05, size: CGSize(width: 3, height: 3),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: inputAt.addingTimeInterval(Double(index)))
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: path, transform: .identity, mask: nil, randomSeed: UInt32(index + 1))
        }))
    }
}
#endif

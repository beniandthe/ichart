#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PDFKit
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Full native source preparation, explicit label review, atomic commit, and
/// existing editor/PDF rendering. All music and handwriting here is synthetic.
@MainActor
final class ChordInkEndingWorkflowTests: XCTestCase {
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testCustomEndingFromInkExcludesFollowingOpenChordAndPreservesExistingMusic() async throws {
        for (style, label) in [(EndingEndStyle.closed, "1–3, 5"), (.open, "On cue")] {
            var chart = Chart.blank(title: "Ending workflow proof", measureCount: 3, layoutStyle: .simpleChordSheet)
            let ids = chart.measures.map(\.id)
            for (index, text) in ["Db", "Eb", "Ab"].enumerated() {
                XCTAssertTrue(chart.appendRecognizedChord(try ChordSymbolParser.parse(text), rawInput: text,
                    to: ids[index], atFraction: 0.15))
            }
            for systemIndex in chart.systems.indices {
                for measureIndex in chart.systems[systemIndex].measures.indices {
                    chart.systems[systemIndex].measures[measureIndex].authoringState =
                        chart.systems[systemIndex].measures[measureIndex].id == ids[2] ? .open : .committed
                    chart.systems[systemIndex].measures[measureIndex].manualLayoutWidth = 180
                }
            }
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1]))
            let existingRepeat = try XCTUnwrap(chart.roadmapObject(id: repeatID))
            let fixture = try makeFixture(chart)
            let first = try XCTUnwrap(fixture.layout.systems.first?.measures.first { $0.sourceMeasureID == ids[0] })
            let second = try XCTUnwrap(fixture.layout.systems.first?.measures.first { $0.sourceMeasureID == ids[1] })
            let drawing = bracketDrawing(from: first.frame.minX, through: second.frame.maxX,
                style: style, fixture: fixture, includesLabelInk: true)
            _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
            let before = chart
            let preparation = prepare(drawing, fixture: fixture)

            XCTAssertEqual(preparation.endings.count, 1)
            XCTAssertTrue(preparation.barlines.isEmpty, "Ending hooks and label strokes are not barlines")
            XCTAssertEqual(preparation.recognitionStrokeCount, 0, "The ending label must not reach chord recognition")
            var state = ChordPreviewState()
            state.replaceDraftEndings(with: preparation.endings)
            state.layoutPageSize = pageSize
            let unreviewed = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: state,
                currentDrawing: drawing, coordinateSpace: nil)
            XCTAssertFalse(unreviewed.canConsumeSource)
            XCTAssertEqual(unreviewed.chart, before)
            let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
            let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: request,
                chart: chart, currentState: state, label: label, endStyle: style))
            XCTAssertEqual(chart, before, "Review changes only the draft, including if the user then cancels")
            let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
                currentDrawing: drawing, coordinateSpace: nil)

            XCTAssertTrue(outcome.canConsumeSource)
            XCTAssertEqual(outcome.result.renderedEndingCount, 1)
            XCTAssertEqual(outcome.result.renderedChordCount, 0)
            XCTAssertEqual(outcome.result.renderedBarlineCount, 0)
            XCTAssertNil(outcome.chart.pageHandwrittenChordData)
            XCTAssertEqual(outcome.chart.roadmapObject(id: repeatID), existingRepeat)
            let ending = try XCTUnwrap(outcome.chart.roadmapObjects.last { $0.type.isEnding })
            let musicAfter = outcome.chart.measures.map { measure -> Measure in
                var music = measure
                music.roadmapObjectIDs.removeAll { $0 == ending.id }
                return music
            }
            XCTAssertEqual(musicAfter, before.measures,
                "Only the new ending's attachment IDs may change the existing measures")
            XCTAssertEqual(ending.startMeasureID, ids[0])
            XCTAssertEqual(ending.endMeasureID, ids[1], "A-flat after the closing edge stays outside the ending")
            XCTAssertNotEqual(ending.endMeasureID, ids[2])
            XCTAssertEqual(ending.resolvedEndingDisplayText, label)
            XCTAssertEqual(ending.resolvedEndingEndStyle, style)
            let receipt = try PKDrawing(data: XCTUnwrap(ending.sourceInkData))
            XCTAssertEqual(PencilKitInkAdapter.inkStrokes(from: receipt), PencilKitInkAdapter.inkStrokes(from: drawing),
                "The ending retains the original bracket and label punctuation")
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(outcome.chart))
            XCTAssertEqual(reopened, outcome.chart)
            let rendered = LeadSheetPageLayoutEngine.pageLayout(for: reopened, pageSize: pageSize)
            let segment = try XCTUnwrap(rendered.systems.flatMap(\.endingLayouts).first { $0.roadmapObjectID == ending.id })
            XCTAssertEqual(segment.text, label)
            XCTAssertTrue(segment.showsLeadingHook)
            XCTAssertEqual(segment.showsTrailingHook, style == .closed)
            try await retainVisualProofs(chart: reopened, label: style.rawValue, expectedText: label)
            XCTAssertEqual(chart, before, "Neither rendering nor exported proofs may mutate the original chart")
        }
    }

    func testDrawnBarlinesAndEndingShareOneAtomicSourceAndKeepRightBoundaryOnTheLeftMeasure() throws {
        var chart = Chart.draft(title: "Ending with barlines", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let fixture = try makeFixture(chart)
        let left = fixture.lane.minX + fixture.lane.width * 0.30
        let right = fixture.lane.minX + fixture.lane.width * 0.65
        let bracket = bracketDrawing(from: left, through: right, style: .closed, fixture: fixture)
        let drawing = PKDrawing(strokes: bracket.strokes + [left, right].map { x in
            stroke([CGPoint(x: x, y: fixture.lane.minY + fixture.lane.height * 0.08),
                    CGPoint(x: x, y: fixture.lane.maxY - fixture.lane.height * 0.08)], origin: fixture.chordFrame.origin)
        })
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        let before = chart
        let preparation = prepare(drawing, fixture: fixture)
        XCTAssertEqual(preparation.endings.count, 1)
        XCTAssertEqual(preparation.barlines.count, 2)
        XCTAssertEqual(preparation.recognitionStrokeCount, 0)
        let detectedEnding = try XCTUnwrap(preparation.endings.first)
        XCTAssertTrue(detectedEnding.sourceStrokeIndices.isDisjoint(
            with: preparation.barlines.reduce(into: Set<Int>()) { $0.formUnion($1.ownedSourceStrokeIndices) }))
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: preparation.barlines)
        state.replaceDraftEndings(with: preparation.endings)
        state.layoutPageSize = pageSize
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: request,
            chart: chart, currentState: state, label: "3, 4, 7", endStyle: .closed))
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
            currentDrawing: drawing, coordinateSpace: nil)

        XCTAssertTrue(outcome.canConsumeSource)
        XCTAssertEqual(outcome.result.renderedEndingCount, 1)
        XCTAssertEqual(outcome.result.renderedBarlineCount, 2)
        XCTAssertEqual(outcome.chart.measures.count, before.measures.count + 2)
        let ending = try XCTUnwrap(outcome.chart.roadmapObjects.first { $0.type.isEnding })
        XCTAssertEqual(ending.startMeasureID, outcome.chart.measures[1].id)
        XCTAssertEqual(ending.endMeasureID, outcome.chart.measures[1].id)
        XCTAssertNotEqual(ending.endMeasureID, outcome.chart.measures[2].id)
        XCTAssertEqual(chart, before)
    }

    func testAddedLiveInkInvalidatesEndingApprovalAndPreservesTheEntireBatch() throws {
        var chart = Chart.blank(title: "Stale ending review", measureCount: 2, layoutStyle: .simpleChordSheet)
        let fixture = try makeFixture(chart)
        let first = try XCTUnwrap(fixture.layout.systems.first?.measures.first)
        let drawing = bracketDrawing(from: first.frame.minX, through: first.frame.maxX,
            style: .open, fixture: fixture, includesLabelInk: true)
        _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation())
        var state = ChordPreviewState()
        state.replaceDraftEndings(with: prepare(drawing, fixture: fixture).endings)
        state.layoutPageSize = pageSize
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: request,
            chart: chart, currentState: state, label: "On cue", endStyle: .open))
        let extra = stroke([CGPoint(x: fixture.lane.maxX - 20, y: fixture.lane.midY + 15),
            CGPoint(x: fixture.lane.maxX - 12, y: fixture.lane.midY + 30)], origin: fixture.chordFrame.origin)
        let actual = PKDrawing(strokes: drawing.strokes + [extra])
        var changedChart = chart
        _ = changedChart.setPageHandwrittenChordDrawing(actual.dataRepresentation())
        XCTAssertNil(ChordDraftEndingReviewPolicy.reviewedState(for: request, chart: changedChart,
            currentState: state, label: "On cue", endStyle: .open))
        let original = chart
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
            currentDrawing: actual, coordinateSpace: nil)
        XCTAssertFalse(outcome.canConsumeSource)
        XCTAssertTrue(outcome.result.didRejectIncompleteSourceCoverage)
        XCTAssertEqual(outcome.result.renderedEndingCount, 0)
        XCTAssertEqual(outcome.chart, original)
        XCTAssertEqual(chart, original)
        XCTAssertEqual(actual.strokes.count, drawing.strokes.count + 1, "Preparing must never erase the live source")
    }

    private struct Fixture {
        let chart: Chart
        let layout: LeadSheetPageLayout
        let chordFrame: CGRect
        let lane: CGRect
    }

    private func makeFixture(_ chart: Chart) throws -> Fixture {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return Fixture(chart: chart, layout: layout, chordFrame: region.frame,
            lane: try XCTUnwrap(region.inputFrames.first))
    }

    private func bracketDrawing(
        from left: CGFloat, through right: CGFloat, style: EndingEndStyle,
        fixture: Fixture, includesLabelInk: Bool = false
    ) -> PKDrawing {
        let top = fixture.lane.minY + fixture.lane.height * 0.12
        let bottom = fixture.lane.minY + fixture.lane.height * 0.30
        var points = [CGPoint(x: left, y: bottom), CGPoint(x: left, y: top), CGPoint(x: right, y: top)]
        if style == .closed { points.append(CGPoint(x: right, y: bottom)) }
        var strokes = [stroke(points, origin: fixture.chordFrame.origin)]
        if includesLabelInk {
            strokes.append(stroke([CGPoint(x: left + 20, y: fixture.lane.minY + fixture.lane.height * 0.24),
                CGPoint(x: left + 20, y: fixture.lane.minY + fixture.lane.height * 0.40)], origin: fixture.chordFrame.origin))
            strokes.append(stroke([CGPoint(x: left + 28, y: fixture.lane.minY + fixture.lane.height * 0.40)],
                origin: fixture.chordFrame.origin, size: 1))
        }
        return PKDrawing(strokes: strokes)
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.chordFrame,
            pageLayout: fixture.layout, flow: .draftPreview, options: .live, layoutStyle: fixture.chart.layoutStyle))
    }

    private func stroke(_ points: [CGPoint], origin: CGPoint, size: CGFloat = 3) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x - origin.x, y: point.y - origin.y),
                timeOffset: Double(index) * 0.05, size: CGSize(width: size, height: size),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_100)))
    }

    private func retainVisualProofs(chart: Chart, label: String, expectedText: String) async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let environment = ProcessInfo.processInfo.environment
        let configured = environment["ICHART_ENDING_WORKFLOW_QA_OUTPUT"] ?? environment["TEST_RUNNER_ICHART_ENDING_WORKFLOW_QA_OUTPUT"]
        let base = configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = base.appendingPathComponent("ending-\(label)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if configured == nil { try? FileManager.default.removeItem(at: base) } }
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        canvas.recognizesChordInk = false
        canvas.chart = chart
        canvas.interactionMode = .browse
        canvas.overrideUserInterfaceStyle = .light
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let native = UIGraphicsImageRenderer(size: pageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
            canvas.draw(canvas.bounds)
        }
        let image = XCTAttachment(image: native)
        image.name = "ending-workflow-\(label)-native"
        image.lifetime = .keepAlways
        add(image)
        try XCTUnwrap(native.pngData()).write(to: directory.appendingPathComponent("native-page.png"))
        let exported = try await PDFChartExporter(exportDirectory: directory).exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        XCTAssertGreaterThan(document.pageCount, 0)
        let normalized = (document.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        XCTAssertTrue(normalized.contains(expectedText), "The full reviewed custom label survives PDF export")
        let pdf = XCTAttachment(data: try Data(contentsOf: exported.url), uniformTypeIdentifier: "com.adobe.pdf")
        pdf.name = "ending-workflow-\(label).pdf"
        pdf.lifetime = .keepAlways
        add(pdf)
    }
}
#endif

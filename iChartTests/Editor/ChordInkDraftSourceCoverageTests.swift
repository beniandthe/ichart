#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordInkDraftSourceCoverageTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let pageSize = CGSize(width: 900, height: 1_400)

    func testCompleteRealTargetsCoverSourceInBothStylesIncludingUnresolvedDrafts() throws {
        for style in styles {
            var chart = makeChart(style)
            let strokes = [stroke(10), stroke(70), stroke(130)]
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation())
            let source = try XCTUnwrap(chart.pageHandwrittenChordData)
            let decoded = try PKDrawing(data: source)
            var state = makeState(chart, drawings: [PKDrawing(strokes: [decoded.strokes[0]]),
                PKDrawing(strokes: Array(decoded.strokes.dropFirst()))])
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state), style.rawValue)
            state.draftChords[0].selectedText = nil
            state.draftChords[0].isStale = true
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state),
                "Ownership cannot depend on a chord label or whether commit can render it")
            XCTAssertEqual(chart.pageHandwrittenChordData, source)
        }
    }

    func testSkippedNineteenStrokeRawTargetCannotBeErasedByTwoAdmittedDrafts() throws {
        for style in styles {
            var chart = makeChart(style)
            let groups = [[stroke(10)], [stroke(70)], (0..<19).map { stroke(160 + CGFloat($0) * 3) }]
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: groups.flatMap { $0 }).dataRepresentation())
            let decoded = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let state = makeState(chart, drawings: [PKDrawing(strokes: [decoded.strokes[0]]),
                PKDrawing(strokes: [decoded.strokes[1]])])
            XCTAssertTrue(state.canRenderAllDraftChords)
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state), style.rawValue)
            let originalChart = chart
            let result = chart.commitChordInkDraftBatch(state)
            XCTAssertTrue(result.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(result.renderedChordCount, 0)
            XCTAssertEqual(result.renderedBarlineCount, 0)
            XCTAssertEqual(chart, originalChart,
                "Excluded ink must reject before measure materialization, chord commit, or canvas-source clearing")
        }
    }

    func testAddedInkStaleInputDuplicateClaimsAndExtraInputFailClosed() throws {
        var chart = makeChart(.rhythmSectionSheet)
        let original = PKDrawing(strokes: [stroke(10), stroke(70)])
        _ = chart.setPageHandwrittenChordDrawing(original.dataRepresentation())
        let decoded = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let full = makeState(chart, drawings: [decoded])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: full))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: decoded, current: decoded))
        let addedInk = PKDrawing(strokes: decoded.strokes + [stroke(130)])
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: decoded, current: addedInk))
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: decoded,
            current: PKDrawing(strokes: decoded.strokes + decoded.strokes)))
        _ = chart.setPageHandwrittenChordDrawing(addedInk.dataRepresentation())
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: full))
        _ = chart.setPageHandwrittenChordDrawing(original.dataRepresentation())
        let duplicate = makeState(chart, drawings: [decoded, decoded])
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: duplicate))
        let extra = makeState(chart, drawings: [PKDrawing(strokes: decoded.strokes + [stroke(130)])])
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: extra))
        let missing = makeState(chart, drawings: [PKDrawing(strokes: [decoded.strokes[0]])])
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: missing))
    }

    func testExactMultisetCountsIdenticalSourceStrokes() throws {
        var chart = makeChart(.simpleChordSheet)
        let repeated = stroke(10)
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [repeated, repeated]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: makeState(chart, drawings: [PKDrawing(strokes: [source.strokes[0]])])))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: makeState(chart, drawings: [source])))
    }

    func testExactPathChronologyTransformAndSeedAreRequiredButColorAndInkTypeAreNot() throws {
        var chart = makeChart(.rhythmSectionSheet)
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(10)]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let original = try XCTUnwrap(source.strokes.first)
        let recolored = PKStroke(ink: PKInk(.marker, color: .red), path: original.path,
            transform: original.transform, mask: nil, randomSeed: original.randomSeed)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: makeState(chart, drawings: [PKDrawing(strokes: [recolored])])))
        let variants = [stroke(10, timeStep: 0.2), stroke(10, creation: 101),
            stroke(10, transform: CGAffineTransform(translationX: 0.25, y: 0)),
            stroke(10, seed: 18), stroke(10, size: 4), stroke(10, force: 0.5),
            stroke(10, opacity: 0.5), stroke(10, azimuth: 0.2), stroke(10, altitude: 0.9),
            stroke(10, secondaryScale: 0.7), stroke(10.25)]
        for altered in variants {
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
                state: makeState(chart, drawings: [PKDrawing(strokes: [altered])])),
                "Bounds/approximate shapes must never stand in for exact source ink")
        }
        if #available(iOS 26.0, *) {
            let points = original.path.map { point in
                PKStrokePoint(location: point.location, timeOffset: point.timeOffset, size: point.size,
                    opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude,
                    secondaryScale: point.secondaryScale, threshold: 0.25)
            }
            let altered = PKStroke(ink: original.ink,
                path: PKStrokePath(controlPoints: points, creationDate: original.path.creationDate),
                transform: original.transform, mask: nil, randomSeed: original.randomSeed)
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
                state: makeState(chart, drawings: [PKDrawing(strokes: [altered])])))
        }
    }

    func testFreshBarlineOnlyAndMixedCoverageRejectsUnknownStaleAndRepeatedOwnership() throws {
        for style in styles {
            var chart = makeChart(style)
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
            let lane = try XCTUnwrap(region.inputFrames.first)
            let localX = lane.midX - region.frame.minX
            let localY = lane.midY - region.frame.minY
            let line = stroke(points: [CGPoint(x: localX, y: localY - lane.height * 0.4),
                CGPoint(x: localX, y: localY + lane.height * 0.4)])
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [line]).dataRepresentation())
            var state = try barlineState(chart)
            XCTAssertEqual(state.draftBarlines.count, 1, style.rawValue)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state), style.rawValue)
            state.draftBarlines[0].id = UUID()
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
            var stale = state
            stale.draftBarlines[0].sourceStrokeIndex = nil
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: stale))
            stale.draftBarlines[0].sourceStrokeIndex = 99
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: stale))
            stale = state
            stale.draftBarlines[0].metrics.height += 1
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: stale))
            stale = state
            stale.draftBarlines.append(state.draftBarlines[0])
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: stale))
            stale = state
            stale.layoutPageSize = nil
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: stale))
            let chord = stroke(points: [CGPoint(x: localX - 80, y: localY - 8),
                CGPoint(x: localX - 65, y: localY + 8)])
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [line, chord]).dataRepresentation())
            let mixedSource = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            var mixed = makeState(chart, drawings: [PKDrawing(strokes: [mixedSource.strokes[1]])])
            mixed.draftBarlines = try barlineState(chart).draftBarlines
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: mixed), style.rawValue)
            // A target cannot double-claim a stroke already represented by a barline.
            mixed.draftChords = makeState(chart, drawings: [mixedSource]).draftChords
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: mixed))
        }
    }

    func testBitmapFragmentsRequireEveryVisiblePieceAndCannotMasqueradeAsOneToOneBarlines() throws {
        var chart = makeChart(.simpleChordSheet)
        let mask = UIBezierPath()
        mask.append(UIBezierPath(rect: CGRect(x: -2, y: -8, width: 16, height: 16)))
        mask.append(UIBezierPath(rect: CGRect(x: 36, y: -8, width: 16, height: 16)))
        let masked = stroke(points: stride(from: 0, through: 50, by: 10).map { CGPoint(x: CGFloat($0), y: 0) }, mask: mask)
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [masked]).dataRepresentation())
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: source)
        XCTAssertEqual(context.drawing.strokes.count, 2)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: makeState(chart, drawings: context.drawing.strokes.map { PKDrawing(strokes: [$0]) })))
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart,
            state: makeState(chart, drawings: [PKDrawing(strokes: [context.drawing.strokes[0]])])))
        let candidate = DraftBarline(measureID: try XCTUnwrap(chart.measures.first?.id), measureIndex: 1,
            fraction: 0.5, sourceStrokeIndex: 0,
            metrics: .init(height: 30, width: 1, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 1))
        var state = makeState(chart, drawings: [context.drawing])
        state.draftBarlines = [candidate]
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
    }

    func testTinyDrawnMarkBelowRecognitionVisibilityStillRequiresExactOwnershipBeforeClearing() throws {
        for style in styles {
            var chart = makeChart(style)
            // PencilKit expands a small pen nib's render bounds. A preserved
            // affine transform makes this fixture truly smaller on the page,
            // independently of the nib's internal minimum rendering footprint.
            let tiny = stroke(points: [CGPoint(x: 160, y: 10), CGPoint(x: 160.5, y: 10.5)],
                transform: CGAffineTransform(scaleX: 0.1, y: 0.1), size: 0.5)
            _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(10), tiny]).dataRepresentation())
            let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
            let tinySource = source.strokes[1]
            XCTAssertFalse(tinySource.renderBounds.isEmpty)
            XCTAssertFalse(ChordInkDraftVisibleStrokePolicy.isVisible(tinySource),
                "Fixture must be drawn ink below the recognition cutoff; bounds: \(tinySource.renderBounds)")
            XCTAssertEqual(PencilKitInkAdapter.visibleStrokeFragments(from: tinySource).count, 1)
            let omittedDrawing = PKDrawing(strokes: [source.strokes[0]])
            let omitted = makeState(chart, drawings: [omittedDrawing])
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source,
                current: omittedDrawing))
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: omitted))
            let originalChart = chart
            let rejected = chart.commitChordInkDraftBatch(omitted)
            XCTAssertTrue(rejected.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(rejected.renderedChordCount, 0)
            XCTAssertEqual(chart, originalChart, style.rawValue)

            let complete = makeState(chart, drawings: [omittedDrawing, PKDrawing(strokes: [tinySource])])
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: complete))
            let rendered = chart.commitChordInkDraftBatch(complete)
            XCTAssertFalse(rendered.didRejectIncompleteSourceCoverage)
            XCTAssertEqual(rendered.renderedChordCount, 2)
            XCTAssertNil(chart.pageHandwrittenChordData)
        }
    }

    func testNoSourceIsSafeInvalidSourceAndInvalidTargetFailClosed() throws {
        var chart = makeChart(.simpleChordSheet)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: ChordPreviewState()))
        chart.pageHandwrittenChordData = Data("invalid drawing".utf8)
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: ChordPreviewState()))
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(10)]).dataRepresentation())
        var state = makeState(chart, drawings: [PKDrawing(strokes: [stroke(10)])])
        state.draftChords[0].drawingData = Data("invalid target".utf8)
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state))
        let hiddenMask = UIBezierPath(rect: CGRect(x: 500, y: 500, width: 20, height: 20))
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: [stroke(points: [
            CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 20)], mask: hiddenMask)]).dataRepresentation())
        let erased = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertTrue(PencilKitInkAdapter.visibleStrokeFragments(from: erased.strokes[0]).isEmpty)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: erased, current: PKDrawing()))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: ChordPreviewState()),
            "Fully mask-erased source ink is explicitly excluded; no visible ink can be lost")
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Source coverage", layoutStyle: style)
        chart.completeInitialSetup(title: "Source coverage", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        return chart
    }
    private func makeState(_ chart: Chart, drawings: [PKDrawing]) -> ChordPreviewState {
        let measureID = chart.measures[0].id
        let drafts = drawings.enumerated().map { index, drawing in
            ChordInkDraft(input: ChordInkDraftInput(measureID: measureID, measureIndex: 1,
                targetFraction: Double(index + 1) / Double(drawings.count + 1), layoutPageSize: pageSize,
                drawingData: drawing.dataRepresentation(), candidateTexts: ["C"], bestCandidateText: "C",
                confidence: 4, strokeCount: drawing.strokes.count))
        }
        return ChordPreviewState(draftChords: drafts, layoutPageSize: pageSize)
    }
    private func barlineState(_ chart: Chart) throws -> ChordPreviewState {
        let source = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        let context = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: source)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: context.drawing),
            chordFrame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), pageLayout: layout)
        let safe = context.barlineRecognitionWithUnambiguousSourceStrokes(recognition)
        return ChordPreviewState(draftBarlines: context.remappedBarlineRecognition(safe).barlines,
            layoutPageSize: pageSize)
    }
    private func stroke(_ x: CGFloat, timeStep: Double = 0.1, creation: Double = 100,
                        transform: CGAffineTransform = .identity, seed: UInt32 = 17,
                        size: CGFloat = 3, force: CGFloat = 1, opacity: CGFloat = 1,
                        azimuth: CGFloat = 0, altitude: CGFloat = .pi / 2, secondaryScale: CGFloat = 1) -> PKStroke {
        stroke(points: [CGPoint(x: x, y: 10), CGPoint(x: x + 14, y: 30)], timeStep: timeStep,
            creation: creation, transform: transform, seed: seed, size: size, force: force,
            opacity: opacity, azimuth: azimuth, altitude: altitude, secondaryScale: secondaryScale)
    }
    private func stroke(points: [CGPoint], timeStep: Double = 0.1, creation: Double = 100,
                        transform: CGAffineTransform = .identity, seed: UInt32 = 17,
                        size: CGFloat = 3, force: CGFloat = 1, opacity: CGFloat = 1,
                        azimuth: CGFloat = 0, altitude: CGFloat = .pi / 2, secondaryScale: CGFloat = 1,
                        mask: UIBezierPath? = nil) -> PKStroke {
        let controls = points.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * timeStep,
                size: CGSize(width: size, height: size), opacity: opacity, force: force,
                azimuth: azimuth, altitude: altitude, secondaryScale: secondaryScale)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controls, creationDate: Date(timeIntervalSinceReferenceDate: creation)),
            transform: transform, mask: mask, randomSeed: seed)
    }
}
#endif

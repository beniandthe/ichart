#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordDraftRepeatReviewUITests: XCTestCase {
    func testBeginningConfirmationUpdatesOnlyTheFirstCurrentClosingSign() throws {
        let chart = chartWithInk()
        let first = sign(in: chart, fraction: 0.3, sourceIndex: 0)
        let second = sign(in: chart, fraction: 0.8, sourceIndex: 1)
        let state = preview([first, second])
        let request = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state))
        XCTAssertEqual(request.draftID, first.id)
        let confirmed = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: state))
        XCTAssertTrue(confirmed.draftBarlines[0].repeatFromBeginningConfirmed)
        XCTAssertFalse(confirmed.draftBarlines[1].repeatFromBeginningConfirmed)
        XCTAssertEqual(confirmed.draftBarlines.map(\.id), state.draftBarlines.map(\.id))
        XCTAssertEqual(ChordInkRepeatSignPairingPolicy.review(state: confirmed).unconfirmedEndIDs, [second.id])
        XCTAssertEqual(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: confirmed)?.draftID, second.id)
        XCTAssertFalse(state.draftBarlines[0].repeatFromBeginningConfirmed)
        XCTAssertEqual(chart.pageHandwrittenChordData, request.sourceDrawingData)
    }

    func testDecliningReviewLeavesCurrentInkAndDraftsUnchangedAndUnrenderable() throws {
        let chart = chartWithInk()
        let state = preview([sign(in: chart)])
        let originalChart = chart
        let originalState = state
        let request = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state))
        // Keep Editing dismisses this value without applying confirmedState.
        XCTAssertEqual(request.state, originalState)
        XCTAssertEqual(chart, originalChart)
        XCTAssertEqual(state, originalState)
        XCTAssertFalse(ChordInkRepeatSignPairingPolicy.review(state: state).canRender)
        XCTAssertNotNil(chart.pageHandwrittenChordData)
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData)).strokes.count, 2)
    }

    func testChangedSourceOrDraftCannotReuseAnEarlierConfirmation() throws {
        let chart = chartWithInk()
        let state = preview([sign(in: chart)])
        let request = try XCTUnwrap(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: state))
        var variants = [ChordPreviewState]()
        var changed = state
        changed.draftBarlines[0].sourceStrokeGeometry[0].points[0].x += 0.25
        variants.append(changed)
        changed = state
        changed.draftBarlines[0].sourceStrokeIndices.insert(4)
        variants.append(changed)
        changed = state
        changed.draftBarlines[0].kind = .single
        variants.append(changed)
        changed = state
        changed.draftBarlines[0].fraction += 0.001
        variants.append(changed)
        changed = state
        changed.draftBarlines[0].metrics.height += 1
        variants.append(changed)
        changed = state
        changed.layoutPageSize = CGSize(width: 1000, height: 1400)
        variants.append(changed)
        changed = state
        changed.draftBarlines[0].id = UUID()
        variants.append(changed)
        for stale in variants {
            XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: stale))
            XCTAssertFalse(stale.draftBarlines[0].repeatFromBeginningConfirmed)
        }
        var changedChart = chart
        changedChart.pageHandwrittenChordData = PKDrawing().dataRepresentation()
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: changedChart, currentState: state))
        changedChart = chart
        changedChart.id = UUID()
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: changedChart, currentState: state))
        changedChart = chart
        changedChart.layoutStyle = .rhythmSectionSheet
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: changedChart, currentState: state))
        changed = state
        changed.updatedAt = Date(timeIntervalSince1970: 500)
        XCTAssertNotNil(ChordDraftRepeatReviewPolicy.confirmedState(for: request, chart: chart, currentState: changed),
            "A bookkeeping timestamp does not change the reviewed source or signs.")
    }

    func testUnmatchedAndNestedStartsBlockWithoutPresentingBeginningConfirmation() {
        let chart = chartWithInk()
        let start = sign(in: chart, kind: .repeatStart, fraction: 0.2)
        let unmatched = preview([start])
        XCTAssertNotNil(ChordDraftRepeatReviewPolicy.blockingMessage(for: unmatched))
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: unmatched))
        let nested = preview([start, sign(in: chart, kind: .repeatStart, fraction: 0.5, sourceIndex: 1),
                              sign(in: chart, fraction: 0.8, sourceIndex: 2)])
        XCTAssertTrue(ChordDraftRepeatReviewPolicy.blockingMessage(for: nested)?.contains("before the previous repeat has ended") == true)
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: nested))
        XCTAssertTrue(nested.draftBarlines.allSatisfy { !$0.repeatFromBeginningConfirmed })
        let paired = preview([start, sign(in: chart, fraction: 0.8, sourceIndex: 1)])
        XCTAssertNil(ChordDraftRepeatReviewPolicy.blockingMessage(for: paired))
        XCTAssertNil(ChordDraftRepeatReviewPolicy.confirmation(for: chart, state: paired))
        XCTAssertTrue(ChordInkRepeatSignPairingPolicy.review(state: paired).canRender)
    }

    func testDetectionPublicationIncludesKindGroupingAndGeometryButIgnoresReviewOnlyChanges() {
        let chart = chartWithInk()
        let original = sign(in: chart)
        var refreshed = original
        refreshed.id = UUID()
        refreshed.repeatFromBeginningConfirmed = true
        XCTAssertTrue(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [refreshed]))
        var changed = original
        changed.kind = .repeatBoth
        XCTAssertFalse(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [changed]))
        changed = original
        changed.sourceStrokeIndices.insert(3)
        XCTAssertFalse(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [changed]))
        changed = original
        changed.sourceStrokeGeometry[0].points[0].x += 0.1
        XCTAssertFalse(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [changed]))
        changed = original
        changed.fraction += 0.001
        XCTAssertFalse(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [changed]))
        changed = original
        changed.metrics.height += 0.1
        XCTAssertFalse(ChordDraftBarlinePresentationPolicy.detectedContentMatches([original], [changed]))
    }

    func testPreviewGeometryAndNativeRasterShowCorrectRepeatDirections() throws {
        let chart = chartWithInk()
        let kinds: [DraftBarlineKind] = [.single, .repeatStart, .repeatEnd, .repeatBoth]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 140), format: format)
        let image = renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: 480, height: 140)).fill()
            for (index, kind) in kinds.enumerated() {
                let frame = CGRect(x: CGFloat(index) * 120 + 20, y: 20, width: 80, height: 80)
                let draft = sign(in: chart, kind: kind)
                let geometry = ChordDraftBarlinePreviewDrawing.geometry(for: draft, in: frame, chart: chart, selected: false)
                XCTAssertEqual(geometry.barXs.count, kind == .single ? 1 : 2)
                XCTAssertEqual(geometry.dotFrames.count, kind == .single ? 0 : (kind == .repeatBoth ? 4 : 2))
                if kind == .repeatStart {
                    XCTAssertTrue(geometry.dotFrames.allSatisfy { $0.minX > (geometry.barXs.max() ?? .infinity) })
                }
                if kind == .repeatEnd {
                    XCTAssertTrue(geometry.dotFrames.allSatisfy { $0.maxX < (geometry.barXs.min() ?? -.infinity) })
                }
                if kind == .repeatBoth {
                    XCTAssertEqual(geometry.dotFrames.filter { $0.maxX < geometry.boundaryX }.count, 2)
                    XCTAssertEqual(geometry.dotFrames.filter { $0.minX > geometry.boundaryX }.count, 2)
                }
                ChordDraftBarlinePreviewDrawing.draw(draft, in: frame, chart: chart, color: .systemBlue, selected: false)
                (kind.displayName as NSString).draw(at: CGPoint(x: CGFloat(index) * 120 + 5, y: 115),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.black])
            }
        }
        XCTAssertNotNil(image.cgImage)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 500)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Automatic repeat draft preview — barline, start, end, both"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(kinds.map(ChordDraftBarlinePresentationPolicy.previewText), ["|", "||:", ":||", ":||:"])
        XCTAssertEqual(ChordDraftBarlinePresentationPolicy.accessibilitySummary(for: kinds.map { sign(in: chart, kind: $0) }),
            "draft signs: Barline, Start repeat, End repeat, End and start repeat")
    }

    private func preview(_ signs: [DraftBarline]) -> ChordPreviewState {
        var state = ChordPreviewState()
        state.draftBarlines = signs
        state.layoutPageSize = CGSize(width: 900, height: 1400)
        return state
    }

    private func sign(in chart: Chart, kind: DraftBarlineKind = .repeatEnd, fraction: Double = 0.5, sourceIndex: Int = 0) -> DraftBarline {
        DraftBarline(measureID: chart.measures[0].id, measureIndex: 0, fraction: fraction,
            layoutPageSize: CGSize(width: 900, height: 1400), sourceStrokeIndex: sourceIndex,
            metrics: .init(height: 60, width: 1, angleDegreesFromVertical: 0, straightness: 1, laneCoverage: 0.8),
            kind: kind, sourceStrokeIndices: [sourceIndex],
            sourceStrokeGeometry: [InkStroke(points: [InkPoint(x: 40, y: 10, timeOffset: 0), InkPoint(x: 40, y: 70, timeOffset: 0.1)])])
    }

    private func chartWithInk() -> Chart {
        var chart = Chart.blank(title: "Repeat review", measureCount: 4, layoutStyle: .simpleChordSheet)
        let strokes = (0..<2).map { index in
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: [10.0, 70.0].enumerated().map { offset, y in
                PKStrokePoint(location: CGPoint(x: CGFloat(40 + index * 20), y: CGFloat(y)), timeOffset: Double(offset) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(index))), mask: nil)
        }
        _ = chart.setPageHandwrittenChordDrawing(PKDrawing(strokes: strokes).dataRepresentation())
        return chart
    }
}
#endif

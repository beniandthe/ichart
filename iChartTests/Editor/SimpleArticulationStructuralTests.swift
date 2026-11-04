#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class SimpleArticulationStructuralTests: XCTestCase {
    private let size = CGSize(width: 932, height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight)

    func testSplitAndJoinFollowExactChordIDsWithoutChangingPaperArchives() throws {
        var chart = Chart.blank(title: "Simple marks and divider", measureCount: 2, layoutStyle: .simpleChordSheet)
        let firstID = chart.measures[0].id
        let followingID = chart.measures[1].id
        let cID = try addChord("C", measureID: firstID, fraction: 0.18, chart: &chart)
        let gID = try addChord("G7", measureID: firstID, fraction: 0.76, chart: &chart)
        _ = chart.applyMeterChange(Meter(numerator: 3, denominator: 4), after: firstID, scope: .toEndOfPiece)
        let changeID = try XCTUnwrap(chart.timeSignatureChanges.first?.id)
        let space = try paperSpace(chart)
        let c = mark(kind: .fermata, measureID: firstID, chordID: cID, space: space,
            current: point(150, 220), source: point(120, 180), seed: 1)
        let g = mark(kind: .accent, measureID: firstID, chordID: gID, space: space,
            current: point(360, 220), source: point(180, 170), seed: 2)
        let floating = mark(kind: .accent, measureID: nil, chordID: nil, space: space,
            current: point(430, 300), source: point(420, 290), seed: 3)
        chart.freeInkArticulations = [c, g, floating]
        let originals = chart.freeInkArticulations

        let rightID = try XCTUnwrap(chart.splitSimpleChordMeasure(firstID, atFraction: 0.5))
        XCTAssertEqual(chart.freeInkArticulations[0].measureID, firstID)
        XCTAssertEqual(chart.freeInkArticulations[1].measureID, rightID)
        XCTAssertEqual(chart.freeInkArticulations[1].attachment, .chord(id: gID))
        XCTAssertNil(chart.freeInkArticulations[2].measureID)
        XCTAssertEqual(chart.timeSignatureChanges.first?.id, changeID)
        XCTAssertEqual(chart.timeSignatureChanges.first?.afterMeasureID, rightID)
        XCTAssertEqual(chart.measure(id: rightID)?.resolvedMeter(defaultMeter: chart.defaultMeter), Meter(numerator: 4, denominator: 4))
        try assertArchives(originals, in: try reopen(chart))

        XCTAssertTrue(chart.canJoinMeasure(after: firstID))
        XCTAssertTrue(chart.joinMeasure(after: firstID))
        XCTAssertEqual(chart.measures.map(\.id), [firstID, followingID])
        XCTAssertEqual(chart.freeInkArticulations[0].measureID, firstID)
        XCTAssertEqual(chart.freeInkArticulations[1].measureID, firstID)
        XCTAssertEqual(chart.freeInkArticulations[1].attachment, .chord(id: gID))
        try assertArchives(originals, in: try reopen(chart))
    }

    func testDeletingChordLeavesMarkFloatingAtItsStagedVisiblePosition() throws {
        var chart = Chart.blank(title: "Delete chord with mark", measureCount: 2, layoutStyle: .simpleChordSheet)
        let measureID = chart.measures[0].id
        let chordID = try addChord("C", measureID: measureID, fraction: 0.35, chart: &chart)
        let space = try paperSpace(chart)
        let original = mark(kind: .fermata, measureID: measureID, chordID: chordID, space: space,
            current: point(80, 90), source: point(110, 130), seed: 4)
        chart.freeInkArticulations = [original]
        let beforeLayout = layout(chart)
        let before = try XCTUnwrap(FreeInkArticulationPlacement.target(for: original, chart: chart, pageLayout: beforeLayout))
        let expected = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at: before.center, pageLayout: beforeLayout))
        chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: chart, pageLayout: beforeLayout)

        XCTAssertTrue(chart.deleteChordEvent(chordID))
        let reopened = try reopen(chart)
        let saved = try XCTUnwrap(reopened.freeInkArticulations.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertNil(saved.measureID)
        XCTAssertNil(saved.attachment)
        XCTAssertNil(saved.beatIndex)
        XCTAssertEqual(saved.pagePoint, expected)
        XCTAssertNotEqual(saved.pagePoint, original.pagePoint)
        XCTAssertEqual(saved.sourcePagePoint, original.sourcePagePoint)
        XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
        let floating = try XCTUnwrap(FreeInkArticulationPlacement.target(for: saved, chart: reopened, pageLayout: layout(reopened)))
        XCTAssertEqual(floating.center, before.center)
    }

    func testSplitThenJoinKeepsFollowingMeterReceiptAndArticulationPaperArchives() throws {
        var chart = Chart.blank(title: "Split and join before meter change", measureCount: 2, layoutStyle: .simpleChordSheet)
        let firstID = chart.measures[0].id
        let followingID = chart.measures[1].id
        let cID = try addChord("C", measureID: firstID, fraction: 0.18, chart: &chart)
        let gID = try addChord("G7", measureID: firstID, fraction: 0.76, chart: &chart)
        _ = chart.applyMeterChange(Meter(numerator: 3, denominator: 4), after: firstID, scope: .toEndOfPiece)
        let receipt = try XCTUnwrap(chart.timeSignatureChanges.first)
        let space = try paperSpace(chart)
        chart.freeInkArticulations = [
            mark(kind: .fermata, measureID: firstID, chordID: cID, space: space,
                current: point(150, 220), source: point(120, 180), seed: 10),
            mark(kind: .accent, measureID: firstID, chordID: gID, space: space,
                current: point(360, 220), source: point(180, 170), seed: 11)
        ]
        let originalMarks = chart.freeInkArticulations
        let rightID = try XCTUnwrap(chart.splitSimpleChordMeasure(firstID, atFraction: 0.5))
        XCTAssertEqual(chart.timeSignatureChanges.first?.id, receipt.id)
        XCTAssertEqual(chart.timeSignatureChanges.first?.afterMeasureID, rightID)
        XCTAssertTrue(chart.joinMeasure(after: firstID))

        let reopened = try reopen(chart)
        XCTAssertEqual(reopened.measures.map(\.id), [firstID, followingID])
        XCTAssertEqual(reopened.timeSignatureChanges.count, 1)
        XCTAssertEqual(reopened.timeSignatureChanges.first?.id, receipt.id)
        XCTAssertEqual(reopened.timeSignatureChanges.first?.afterMeasureID, firstID)
        XCTAssertEqual(reopened.timeSignatureChanges.first?.meter, receipt.meter)
        XCTAssertEqual(reopened.measure(id: firstID)?.resolvedMeter(defaultMeter: reopened.defaultMeter), Meter(numerator: 4, denominator: 4))
        XCTAssertEqual(reopened.measure(id: followingID)?.resolvedMeter(defaultMeter: reopened.defaultMeter), Meter(numerator: 3, denominator: 4))
        XCTAssertEqual(reopened.freeInkArticulations.map(\.measureID), [firstID, firstID])
        XCTAssertEqual(reopened.freeInkArticulations.map(\.attachment), [.chord(id: cID), .chord(id: gID)])
        try assertArchives(originalMarks, in: reopened)
    }

    func testSingleAndRangeMeasureDeletionKeepDeletedTargetsFloatingAndSurvivorsAttached() throws {
        for deletesRange in [false, true] {
            var chart = Chart.blank(title: "Delete measures with marks", measureCount: 3, layoutStyle: .simpleChordSheet)
            let ids = chart.measures.map(\.id)
            let cID = try addChord("C", measureID: ids[0], fraction: 0.2, chart: &chart)
            let gID = try addChord("G7", measureID: ids[1], fraction: 0.2, chart: &chart)
            let dID = try addChord("D", measureID: ids[2], fraction: 0.2, chart: &chart)
            let space = try paperSpace(chart)
            chart.freeInkArticulations = [
                mark(kind: .fermata, measureID: ids[0], chordID: cID, space: space, current: point(150, 220), source: point(110, 130), seed: 5),
                mark(kind: .accent, measureID: ids[1], chordID: gID, space: space, current: point(300, 220), source: point(270, 130), seed: 6),
                mark(kind: .fermata, measureID: ids[2], chordID: dID, space: space, current: point(450, 220), source: point(430, 130), seed: 7)
            ]
            chart = FreeInkArticulationPlacement.preservingVisiblePagePoints(in: chart, pageLayout: layout(chart))
            let originals = chart.freeInkArticulations
            if deletesRange {
                XCTAssertTrue(chart.canDeleteMeasures(from: ids[0], through: ids[1]))
                XCTAssertTrue(chart.deleteMeasures(from: ids[0], through: ids[1]))
            } else {
                XCTAssertTrue(chart.canDeleteMeasure(id: ids[1]))
                XCTAssertTrue(chart.deleteMeasure(id: ids[1]))
            }
            let reopened = try reopen(chart)
            try assertArchives(originals, in: reopened)
            for (index, original) in originals.enumerated() {
                let saved = try XCTUnwrap(reopened.freeInkArticulations.first { $0.id == original.id })
                if index == 1 || (deletesRange && index == 0) {
                    XCTAssertNil(saved.measureID)
                    XCTAssertNil(saved.attachment)
                    XCTAssertEqual(saved.pagePoint, original.pagePoint)
                } else {
                    XCTAssertEqual(saved.attachment, original.attachment)
                    XCTAssertEqual(saved.measureID, original.measureID)
                }
            }
        }
    }

    func testLegacySourcePointIsCapturedBeforeItsSourceMeasureIsMergedOrDeleted() throws {
        for deletesMeasure in [false, true] {
            var chart = Chart.blank(title: "Legacy mark source", measureCount: 3, layoutStyle: .simpleChordSheet)
            let ids = chart.measures.map(\.id)
            let cID = try addChord("C", measureID: ids[0], fraction: 0.2, chart: &chart)
            _ = try addChord("G7", measureID: ids[1], fraction: 0.2, chart: &chart)
            let sourceLayout = layout(chart)
            let frame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
            var space = try paperSpace(chart)
            let sourceAnchor = try XCTUnwrap(space.measureAnchors?.first { $0.measureID == ids[1] })
            space.measureAnchors = [sourceAnchor]
            space.chordAnchors = nil
            let source = point(Double(sourceAnchor.frame.rect.midX + frame.minX - sourceLayout.paperFrame.minX),
                Double(sourceAnchor.frame.rect.midY + frame.minY - sourceLayout.paperFrame.minY))
            var original = mark(kind: .accent, measureID: ids[0], chordID: cID, space: space,
                current: point(140, 180), source: source, seed: 8)
            original.sourceCoordinateSpace = space
            original.sourcePagePoint = nil
            let archive = try PKDrawing(data: original.sourceInkData)
            let expectedSource = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at:
                CGPoint(x: archive.bounds.midX + frame.minX, y: archive.bounds.midY + frame.minY),
                pageLayout: sourceLayout))
            chart.freeInkArticulations = [original]

            if deletesMeasure {
                XCTAssertTrue(chart.deleteMeasure(id: ids[1]))
            } else {
                XCTAssertTrue(chart.joinMeasure(after: ids[0]))
            }
            let reopened = try reopen(chart)
            let saved = try XCTUnwrap(reopened.freeInkArticulations.first)
            XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
            XCTAssertEqual(saved.sourcePagePoint?.pageIndex, 0)
            XCTAssertEqual(try XCTUnwrap(saved.sourcePagePoint?.x), expectedSource.x, accuracy: 0.01)
            XCTAssertEqual(try XCTUnwrap(saved.sourcePagePoint?.y), expectedSource.y, accuracy: 0.01)
            XCTAssertNil(saved.sourceCoordinateSpace?.measureAnchors)
            XCTAssertNil(saved.sourceCoordinateSpace?.chordAnchors)
            XCTAssertEqual(saved.attachment, .chord(id: cID))
            XCTAssertEqual(saved.measureID, ids[0])
        }
    }

    func testClosingOpenMeasureAnchorsLoneChordAndPreservesLegacyArticulationRestorePoint() throws {
        var chart = Chart.blank(title: "Close measure with legacy mark", measureCount: 1,
            layoutStyle: .simpleChordSheet)
        chart.systems[0].measures[0].authoringState = .open
        let measureID = chart.measures[0].id
        let chordID = try addChord("G7", measureID: measureID, fraction: 0.72, chart: &chart)
        chart.systems[0].measures[0].chordEvents[0].startPosition =
            BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 1)
        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: measureID,
            atFraction: nil, visualFraction: 0.72, preserveMusicalPlacement: true))
        let beforeLayout = layout(chart)
        let beforeGlyph = try XCTUnwrap(beforeLayout.systems.flatMap(\.measures)
            .flatMap(\.chordLayouts).first { $0.id == chordID })
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: beforeLayout)
        var space = try paperSpace(chart)
        space.measureAnchors = [try XCTUnwrap(space.measureAnchors?.first { $0.measureID == measureID })]
        space.chordAnchors = [try XCTUnwrap(PersistentInkChordAnchor(measureID: measureID,
            chordID: chordID, frame: beforeGlyph.frame.offsetBy(dx: -frame.minX, dy: -frame.minY)))]
        let source = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at:
            CGPoint(x: beforeGlyph.frame.midX, y: beforeGlyph.frame.minY - 24), pageLayout: beforeLayout))
        var original = mark(kind: .fermata, measureID: measureID, chordID: chordID,
            space: space, current: source, source: source, seed: 12)
        original.sourceCoordinateSpace = space
        original.sourcePagePoint = nil
        let archive = try PKDrawing(data: original.sourceInkData)
        let expectedSource = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at:
            CGPoint(x: archive.bounds.midX + frame.minX, y: archive.bounds.midY + frame.minY),
            pageLayout: beforeLayout))
        chart.freeInkArticulations = [original]

        let nextID = try XCTUnwrap(chart.commitOpenMeasure(barlineAfter: .single))
        let reopened = try reopen(chart)
        XCTAssertEqual(reopened.measures.map(\.id), [measureID, nextID])
        let chord = try XCTUnwrap(reopened.chordEvent(id: chordID))
        XCTAssertEqual(chord.startPosition.beat, 1)
        XCTAssertEqual(chord.startPosition.subdivision, 0)
        XCTAssertTrue(chord.anchorsToMeasureStart)
        XCTAssertNil(chord.manualLaneFraction)
        XCTAssertNil(chord.manualVisualLaneFraction)
        let saved = try XCTUnwrap(reopened.freeInkArticulations.first)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.attachment, .chord(id: chordID))
        XCTAssertEqual(saved.measureID, measureID)
        XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
        XCTAssertEqual(saved.pagePoint, original.pagePoint)
        XCTAssertEqual(saved.sourcePagePoint?.pageIndex, expectedSource.pageIndex)
        XCTAssertEqual(try XCTUnwrap(saved.sourcePagePoint?.x), expectedSource.x, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(saved.sourcePagePoint?.y), expectedSource.y, accuracy: 0.01)
        XCTAssertNil(saved.sourceCoordinateSpace?.measureAnchors)
        XCTAssertNil(saved.sourceCoordinateSpace?.chordAnchors)
        let afterLayout = layout(reopened)
        let afterGlyph = try XCTUnwrap(afterLayout.systems.flatMap(\.measures)
            .flatMap(\.chordLayouts).first { $0.id == chordID })
        XCTAssertLessThan(afterGlyph.frame.minX, beforeGlyph.frame.minX - 20)
        let restoreCenter = try XCTUnwrap(FreeInkArticulationPlacement.center(for: expectedSource,
            pageLayout: afterLayout))
        XCTAssertEqual(restoreCenter.x, archive.bounds.midX + frame.minX, accuracy: 0.01)
        XCTAssertEqual(restoreCenter.y, archive.bounds.midY + frame.minY, accuracy: 0.01)
    }

    func testRhythmArticulationGuardsRemainUnchanged() throws {
        var chart = Chart.blank(title: "Rhythm guard", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let id = chart.measures[0].id
        let chordID = try addChord("C", measureID: id, fraction: 0.2, chart: &chart)
        chart.freeInkArticulations = [mark(kind: .fermata, measureID: id, chordID: chordID,
            space: try paperSpace(chart), current: point(150, 180), source: point(120, 130), seed: 9)]
        XCTAssertFalse(chart.canJoinMeasure(after: id))
        XCTAssertFalse(chart.canDeleteMeasure(id: id))
        XCTAssertFalse(chart.canDeleteMeasures(from: id, through: id))
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
    }

    private func paperSpace(_ chart: Chart) throws -> PersistentInkCoordinateSpace {
        let pageLayout = layout(chart)
        var space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(for: pageLayout,
            relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: pageLayout)))
        if chart.layoutStyle == .simpleChordSheet {
            space.measureAnchors = space.measureAnchors?.map { var anchor = $0; anchor.staffFrame = nil; return anchor }
        }
        return space
    }

    private func addChord(_ text: String, measureID: UUID, fraction: Double, chart: inout Chart) throws -> UUID {
        let id = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse(text), rawInput: text,
            to: measureID, atFraction: fraction))
        if chart.layoutStyle == .simpleChordSheet { _ = chart.setChordEventManualLaneFraction(fraction, for: id) }
        return id
    }

    private func point(_ x: Double, _ y: Double) -> FreeInkArticulationPagePoint {
        FreeInkArticulationPagePoint(pageIndex: 0, x: x, y: y)
    }

    private func mark(kind: FreeInkArticulationKind, measureID: UUID?, chordID: UUID?,
        space: PersistentInkCoordinateSpace, current: FreeInkArticulationPagePoint,
        source: FreeInkArticulationPagePoint, seed: Int) -> FreeInkArticulation {
        let inset = LeadSheetPageLayoutEngine.pageInkWritingInset
        let center = CGPoint(x: source.x - Double(inset), y: source.y - Double(inset))
        let points = [CGPoint(x: center.x - 6, y: center.y - 5), CGPoint(x: center.x + 6, y: center.y),
            CGPoint(x: center.x - 6, y: center.y + 5)]
        let path = points.enumerated().map { index, point in PKStrokePoint(location: point,
            timeOffset: Double(index) * 0.1, size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2) }
        let stroke = PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: path, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
        var archiveSpace = space
        archiveSpace.measureAnchors = nil
        archiveSpace.chordAnchors = nil
        return FreeInkArticulation(kind: kind, measureID: measureID,
            sourceInkData: PKDrawing(strokes: [stroke]).dataRepresentation(), sourceCoordinateSpace: archiveSpace,
            attachment: chordID.map { .chord(id: $0) }, pagePoint: current, sourcePagePoint: source)
    }

    private func assertArchives(_ originals: [FreeInkArticulation], in chart: Chart) throws {
        XCTAssertEqual(chart.freeInkArticulations.map(\.id), originals.map(\.id))
        for original in originals {
            let saved = try XCTUnwrap(chart.freeInkArticulations.first { $0.id == original.id })
            XCTAssertEqual(saved.kind, original.kind)
            XCTAssertEqual(saved.sourceInkData, original.sourceInkData)
            XCTAssertEqual(saved.sourcePagePoint, original.sourcePagePoint)
            XCTAssertEqual(saved.pagePoint, original.pagePoint)
        }
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library-state.json")
        try FileChartRepository(url: url).saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        let reopened = try XCTUnwrap(try FileChartRepository(url: url).loadSnapshot()?.charts.first)
        XCTAssertEqual(reopened, chart)
        return reopened
    }
}
#endif

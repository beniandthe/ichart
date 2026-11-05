#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class RhythmDividerLayoutPreservationTests: XCTestCase {
    private let portrait = CGSize(width: 900, height: 1_400)
    private let landscape = CGSize(width: 1_400, height: 900)

    func testAutomaticDistinctUnitDividerStaysProtectedWithUnrelatedStaffInkAcrossRotationAndReopen() throws {
        try assertProtection(widths: .automatic)
    }

    func testMixedWidthDistinctUnitDividerStaysProtectedWithUnrelatedStaffInkAcrossRotationAndReopen() throws {
        for widths in [WidthIntent.mixedLeft, .mixedRight] {
            try assertProtection(widths: widths)
        }
    }

    func testEqualizedDistinctUnitDividerStaysProtectedWithUnrelatedStaffInkAcrossRotationAndReopen() throws {
        try assertProtection(widths: .equalizedFirstRow)
    }

    func testLaterRowDistinctUnitDividerStaysProtectedWithStaffInkInTheSameRow() throws {
        try assertProtection(widths: .automatic, mergesLaterRow: true)
    }

    func testDrawnSiblingDividerCanMergeWithoutMovingUnrelatedStaffInkAcrossRotationAndReopen() throws {
        var chart = Chart.blank(title: "Safe sibling divider reversal", measureCount: 7,
            layoutStyle: .rhythmSectionSheet)
        let originalIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: originalIDs[4]))
        let beforeSplit = layout(chart, size: portrait)
        let firstSystem = try XCTUnwrap(beforeSplit.systems.first)
        let originalMeasure = try measure(originalIDs[0], in: beforeSplit)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: firstSystem, paperFrame: beforeSplit.paperFrame(for: firstSystem)))
        let x = originalMeasure.staffFrame.midX
        var state = ChordPreviewState(layoutPageSize: portrait)
        state.replaceDraftBarlines(with: [DraftBarline(measureID: originalIDs[0], measureIndex: 1,
            fraction: 0.5, laneLocation: .init(systemIndex: firstSystem.index,
                fraction: Double((x - lane.minX) / lane.width)), layoutPageSize: portrait,
            metrics: .init(height: 54, width: 2, angleDegreesFromVertical: 1,
                straightness: 0.98, laneCoverage: 0.9))])
        let split = chart.commitChordInkDraftBatch(state)
        XCTAssertEqual(split.renderedBarlineCount, 1)
        XCTAssertTrue(split.unresolvedDraftIDs.isEmpty)
        let leftID = originalIDs[0]
        let rightID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        XCTAssertNotEqual(rightID, originalIDs[1])
        let group = try XCTUnwrap(chart.measure(id: leftID)?.rhythmSectionSplitLayoutSource?.groupID)
        XCTAssertEqual(chart.measure(id: rightID)?.rhythmSectionSplitLayoutSource?.groupID, group)
        for (index, id) in chart.measures.map(\.id).enumerated() {
            let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("G7"),
                rawInput: "G7", to: id, atFraction: 0.35, sourceInkData: archive(seed: UInt32(700 + index))))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: id, atFraction: nil,
                visualFraction: 0.35, preserveMusicalPlacement: true))
        }

        let authored = layout(chart, size: portrait)
        let writingFrame = LeadSheetActiveInkScope.pageWritingFrame(for: authored)
        let owner = try measure(originalIDs[6], in: authored)
        let ownerPoint = CGPoint(x: owner.staffFrame.midX - writingFrame.minX,
            y: owner.staffFrame.midY - writingFrame.minY)
        let ink = PKDrawing(strokes: [stroke([ownerPoint,
            CGPoint(x: ownerPoint.x + 7, y: ownerPoint.y - 14)], seed: 799)])
        let space = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: authored, relativeTo: writingFrame))
        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(ink.dataRepresentation(), coordinateSpace: space))
        let baseline = chart
        let sourceBytes = try XCTUnwrap(chart.pageHandwrittenNotationData)
        let storedSpace = try XCTUnwrap(chart.pageHandwrittenNotationCoordinateSpace)
        let sourceDrawing = try PKDrawing(data: sourceBytes)
        let source = layout(chart, size: portrait)
        let sourceWidths = Dictionary(source.systems.flatMap(\.measures).compactMap { measure in
            measure.sourceMeasureID.map { ($0, Double(measure.staffFrame.width)) }
        }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(chart.canDeleteCommittedChordBarline(after: leftID))
        XCTAssertTrue(chart.deleteCommittedChordBarline(after: leftID, sourceMeasureWidths: sourceWidths))
        let reopened = try reopen(chart)
        let untouchedIDs = Set(baseline.measures.map(\.id)).subtracting([leftID, rightID])
        XCTAssertEqual(reopened.measures.map(\.id), originalIDs)
        XCTAssertEqual(reopened.pageHandwrittenNotationData, sourceBytes)
        let retainedSpace = try XCTUnwrap(reopened.pageHandwrittenNotationCoordinateSpace)
        XCTAssertEqual(retainedSpace.measureAnchors?.filter { untouchedIDs.contains($0.measureID) },
            storedSpace.measureAnchors?.filter { untouchedIDs.contains($0.measureID) })
        for id in untouchedIDs {
            XCTAssertEqual(reopened.measure(id: id)?.manualLayoutWidth, baseline.measure(id: id)?.manualLayoutWidth)
            XCTAssertEqual(reopened.measure(id: id)?.chordEvents, baseline.measure(id: id)?.chordEvents)
        }
        for size in [portrait, landscape] {
            let oldLayout = layout(baseline, size: size)
            let newLayout = layout(reopened, size: size)
            for id in untouchedIDs {
                let old = try measure(id, in: oldLayout)
                let new = try measure(id, in: newLayout)
                let context = "Safe siblings, viewport \(size)"
                assertFrame(new.frame, equals: old.frame, context: context)
                assertFrame(new.staffFrame, equals: old.staffFrame, context: context)
                assertFrame(new.chordWritingFrame, equals: old.chordWritingFrame, context: context)
                for (oldGlyph, newGlyph) in zip(old.chordLayouts, new.chordLayouts) {
                    assertFrame(newGlyph.frame, equals: oldGlyph.frame, context: context)
                    assertFrame(newGlyph.naturalFrame, equals: oldGlyph.naturalFrame, context: context)
                }
            }
            let oldInk = try projectedDrawing(sourceDrawing, source: storedSpace, layout: oldLayout)
            let newInk = try projectedDrawing(sourceDrawing, source: retainedSpace, layout: newLayout)
            XCTAssertEqual(oldInk.strokes.count, newInk.strokes.count)
            for (oldStroke, newStroke) in zip(oldInk.strokes, newInk.strokes) {
                assertFrame(newStroke.renderBounds, equals: oldStroke.renderBounds,
                    context: "Safe sibling merge retains unrelated ink, viewport \(size)")
            }
        }
    }

    private enum WidthIntent: String {
        case automatic, mixedLeft, mixedRight, equalizedFirstRow
    }

    private func assertProtection(widths: WidthIntent, mergesLaterRow: Bool = false) throws {
        var chart = Chart.blank(title: "Rhythm divider layout preservation",
            measureCount: mergesLaterRow ? 10 : 7, layoutStyle: .rhythmSectionSheet)
        let originalIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: originalIDs[4]))
        if mergesLaterRow { XCTAssertTrue(chart.insertSystemBreak(before: originalIDs[7])) }
        switch widths {
        case .automatic:
            break
        case .mixedLeft:
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(100, for: originalIDs[0]))
        case .mixedRight:
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(100, for: originalIDs[1]))
        case .equalizedFirstRow:
            for id in originalIDs.prefix(4) {
                XCTAssertNotNil(chart.setMeasureManualLayoutWidth(140, for: id))
            }
        }
        for (index, id) in originalIDs.enumerated() {
            let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse(index.isMultiple(of: 2) ? "Cmaj7" : "G7"),
                rawInput: index.isMultiple(of: 2) ? "Cmaj7" : "G7", to: id,
                atFraction: 0.35, sourceInkData: archive(seed: UInt32(100 + index))))
            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: id, atFraction: nil,
                visualFraction: 0.35, preserveMusicalPlacement: true))
        }

        let leftID = originalIDs[mergesLaterRow ? 4 : 0]
        let removedID = originalIDs[mergesLaterRow ? 5 : 1]
        // In the later-row case this is the untouched third measure of the
        // joined row; otherwise it is safely in another musical row.
        let inkOwnerID = originalIDs[6]
        let authoredLayout = layout(chart, size: portrait)
        XCTAssertEqual(authoredLayout.systems.first?.measures.compactMap(\.sourceMeasureID),
            Array(originalIDs.prefix(4)), "The first row must own four real sizing units before the merge")
        let writingFrame = LeadSheetActiveInkScope.pageWritingFrame(for: authoredLayout)
        let sourceSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: authoredLayout, relativeTo: writingFrame))
        let owner = try measure(inkOwnerID, in: authoredLayout)
        let x = owner.staffFrame.midX - writingFrame.minX
        let y = owner.staffFrame.midY - writingFrame.minY
        let staffInk = PKDrawing(strokes: [stroke([
            CGPoint(x: x, y: y), CGPoint(x: x + 5, y: y - 2),
            CGPoint(x: x + 9, y: y), CGPoint(x: x + 4, y: y + 2), CGPoint(x: x, y: y)
        ], seed: 501), stroke([
            CGPoint(x: x + 9, y: y), CGPoint(x: x + 9, y: y - 22)
        ], seed: 502)])
        XCTAssertTrue(chart.setPageHandwrittenNotationDrawing(staffInk.dataRepresentation(),
            coordinateSpace: sourceSpace))
        let baseline = chart
        let sourceBytes = try XCTUnwrap(baseline.pageHandwrittenNotationData)
        let savedSourceSpace = try XCTUnwrap(baseline.pageHandwrittenNotationCoordinateSpace)
        let storedDrawing = try PKDrawing(data: sourceBytes)
        let sourceLayout = layout(baseline, size: portrait)
        let sourceWidths = Dictionary(sourceLayout.systems.flatMap(\.measures).compactMap { measure in
            measure.sourceMeasureID.map { ($0, Double(measure.staffFrame.width)) }
        }, uniquingKeysWith: { first, _ in first })
        XCTAssertFalse(baseline.canDeleteCommittedChordBarline(after: leftID),
            "Distinct sizing units must remain separate when a merge could reflow retained staff ink")

        XCTAssertFalse(chart.deleteCommittedChordBarline(after: leftID, sourceMeasureWidths: sourceWidths))
        XCTAssertEqual(chart, baseline, "A protected divider must leave the entire chart unchanged")
        let reopened = try reopen(chart)
        let untouchedIDs = Set(originalIDs)
        XCTAssertEqual(reopened.measures.map(\.id), originalIDs)
        XCTAssertNotNil(reopened.measure(id: removedID))
        XCTAssertEqual(reopened.pageHandwrittenNotationData, sourceBytes)
        let retainedSpace = try XCTUnwrap(reopened.pageHandwrittenNotationCoordinateSpace)
        XCTAssertEqual(retainedSpace.measureAnchors?.filter { untouchedIDs.contains($0.measureID) },
            savedSourceSpace.measureAnchors?.filter { untouchedIDs.contains($0.measureID) })
        XCTAssertEqual(retainedSpace.chordAnchors?.filter { untouchedIDs.contains($0.measureID) },
            savedSourceSpace.chordAnchors?.filter { untouchedIDs.contains($0.measureID) })
        for id in untouchedIDs {
            let before = try XCTUnwrap(baseline.measure(id: id))
            let after = try XCTUnwrap(reopened.measure(id: id))
            XCTAssertEqual(after.manualLayoutWidth, before.manualLayoutWidth,
                "Joining elsewhere must retain this measure's automatic/manual sizing intent")
            XCTAssertEqual(after.chordEvents, before.chordEvents)
        }

        for size in [portrait, landscape] {
            let before = layout(baseline, size: size)
            let after = layout(reopened, size: size)
            let context = "\(widths.rawValue), later row \(mergesLaterRow), viewport \(size)"
            for id in untouchedIDs {
                let old = try measure(id, in: before)
                let new = try measure(id, in: after)
                assertFrame(new.frame, equals: old.frame, context: context)
                assertFrame(new.staffFrame, equals: old.staffFrame, context: context)
                assertFrame(new.chordWritingFrame, equals: old.chordWritingFrame, context: context)
                XCTAssertEqual(new.chordLayouts.map(\.id), old.chordLayouts.map(\.id), context)
                for (oldGlyph, newGlyph) in zip(old.chordLayouts, new.chordLayouts) {
                    assertFrame(newGlyph.frame, equals: oldGlyph.frame, context: context)
                    assertFrame(newGlyph.naturalFrame, equals: oldGlyph.naturalFrame, context: context)
                }
            }
            let beforeInk = try projectedDrawing(storedDrawing, source: savedSourceSpace, layout: before)
            let afterInk = try projectedDrawing(storedDrawing, source: retainedSpace, layout: after)
            XCTAssertEqual(afterInk.strokes.count, beforeInk.strokes.count)
            XCTAssertEqual(afterInk.strokes.map(\.randomSeed), beforeInk.strokes.map(\.randomSeed))
            for (oldStroke, newStroke) in zip(beforeInk.strokes, afterInk.strokes) {
                assertFrame(newStroke.renderBounds, equals: oldStroke.renderBounds,
                    context: "Projected unrelated staff ink: \(context)")
                XCTAssertEqual(newStroke.path.count, oldStroke.path.count)
                for index in 0..<min(oldStroke.path.count, newStroke.path.count) {
                    let oldPoint = oldStroke.path[index].location.applying(oldStroke.transform)
                    let newPoint = newStroke.path[index].location.applying(newStroke.transform)
                    XCTAssertEqual(newPoint.x, oldPoint.x, accuracy: 0.01, context)
                    XCTAssertEqual(newPoint.y, oldPoint.y, accuracy: 0.01, context)
                }
            }
        }
    }

    private func projectedDrawing(_ drawing: PKDrawing, source: PersistentInkCoordinateSpace,
        layout: LeadSheetPageLayout) throws -> PKDrawing {
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let target = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: frame))
        return LeadSheetPersistentInkCoordinateSpacePolicy.drawing(drawing,
            sourceCoordinateSpace: source, targetCoordinateSpace: target)
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library-state.json")
        try FileChartRepository(url: url).saveSnapshot(.init(charts: [chart], selectedChartID: chart.id,
            entitlements: .free))
        let reopened = try XCTUnwrap(try FileChartRepository(url: url).loadSnapshot()?.charts.first)
        XCTAssertEqual(reopened, chart)
        return reopened
    }

    private func layout(_ chart: Chart, size: CGSize) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size,
            includesChordInkContinuationLanes: true)
    }

    private func measure(_ id: UUID, in layout: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect, context: String,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.01, context, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.01, context, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.01, context, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.01, context, file: file, line: line)
    }

    private func archive(seed: UInt32) -> Data {
        PKDrawing(strokes: [stroke([CGPoint(x: 10, y: 12), CGPoint(x: 20, y: 30)], seed: seed)])
            .dataRepresentation()
    }

    private func stroke(_ points: [CGPoint], seed: UInt32) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.04,
                    size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif

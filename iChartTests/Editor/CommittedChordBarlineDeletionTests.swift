#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CommittedChordBarlineDeletionTests: XCTestCase {
    private let size = CGSize(width: 932, height: 1_100)

    func testGenericDividerDeletionPreservesChordReceiptsAndTransformsVisualFractionsInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Delete chord divider", measureCount: 3, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let left = try event("C△7", fraction: 0.2, seed: 1)
            let right = try event("G7", fraction: 0.8, seed: 2)
            chart.systems[0].measures[0].chordEvents = [left]
            chart.systems[0].measures[1].chordEvents = [right]
            _ = chart.setMeasureManualLayoutWidth(120, for: ids[0])
            _ = chart.setMeasureManualLayoutWidth(240, for: ids[1])
            var untouched = chart.measures[2]
            untouched.index = 2

            XCTAssertTrue(chart.canDeleteCommittedChordBarline(after: ids[0]))
            XCTAssertTrue(chart.deleteCommittedChordBarline(after: ids[0]))
            let reopened = try reopen(chart)
            XCTAssertEqual(reopened.measures.map(\.id), [ids[0], ids[2]])
            XCTAssertEqual(reopened.measures[1], untouched)
            XCTAssertEqual(reopened.measures[0].manualLayoutWidth, 360)
            XCTAssertEqual(reopened.measures[0].chordEvents.map(\.id), [left.id, right.id])
            for (original, fraction) in [(left, 0.2 / 3), (right, 1.0 / 3 + 0.8 * 2 / 3)] {
                let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
                assertReceipt(actual, matches: original)
                XCTAssertEqual(try XCTUnwrap(actual.manualVisualLaneFraction), fraction, accuracy: 0.0001)
                XCTAssertEqual(try XCTUnwrap(actual.manualLaneFraction), fraction, accuracy: 0.0001)
                XCTAssertFalse(actual.anchorsToMeasureStart)
            }
        }
    }

    func testDeletingDividerAroundFinalSingletonAnchorsEitherSideToBeatOne() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for originalSide in [0, 1] {
                var chart = Chart.blank(title: "Singleton after merge", measureCount: 2, layoutStyle: style)
                let leftID = chart.measures[0].id
                let original = try event("F7", fraction: 0.7, seed: 3)
                chart.systems[0].measures[originalSide].chordEvents = [original]

                XCTAssertTrue(chart.deleteCommittedChordBarline(after: leftID))
                let reopened = try reopen(chart)
                XCTAssertEqual(reopened.measures.map(\.id), [leftID])
                let actual = try XCTUnwrap(reopened.chordEvent(id: original.id))
                assertReceipt(actual, matches: original)
                XCTAssertEqual(actual.startPosition, BeatPosition(beat: 1, subdivision: 0, subdivisionsPerBeat: 1))
                XCTAssertTrue(actual.anchorsToMeasureStart)
                XCTAssertNil(actual.manualVisualLaneFraction)
                XCTAssertNil(actual.manualLaneFraction)
            }
        }
    }

    func testMixedAutomaticAndManualWidthsUseComparablePhysicalWeights() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Mixed source widths", measureCount: 3, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            chart.systems[0].measures[0].chordEvents = [try event("C", fraction: 0.2, seed: 6)]
            chart.systems[0].measures[1].chordEvents = [try event("G7", fraction: 0.8, seed: 7)]
            _ = chart.setMeasureManualLayoutWidth(160, for: ids[1])
            let source = layout(chart)
            let measures = source.systems.flatMap(\.measures)
            let lhs = try XCTUnwrap(measures.first { $0.sourceMeasureID == ids[0] })
            let rhs = try XCTUnwrap(measures.first { $0.sourceMeasureID == ids[1] })
            let leftWidth = style == .simpleChordSheet ? lhs.frame.width : lhs.staffFrame.width
            let rightWidth = style == .simpleChordSheet ? rhs.frame.width : rhs.staffFrame.width
            let leftScale = Double(leftWidth / (leftWidth + rightWidth))

            XCTAssertTrue(chart.deleteCommittedChordBarline(after: ids[0]))
            let left = try XCTUnwrap(chart.measures[0].chordEvents.first)
            let right = try XCTUnwrap(chart.measures[0].chordEvents.last)
            XCTAssertEqual(try XCTUnwrap(left.manualVisualLaneFraction), 0.2 * leftScale, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(right.manualVisualLaneFraction), leftScale + 0.8 * (1 - leftScale), accuracy: 0.0001)
            XCTAssertGreaterThan(leftScale, 0.01, "The automatic side cannot collapse to a 1-point weight")
        }
    }

    func testCallerSuppliedWidthsTakePriorityOverStoredWidthWeights() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Live source widths", measureCount: 2, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            chart.systems[0].measures[0].chordEvents = [try event("C", fraction: 0.2, seed: 8)]
            chart.systems[0].measures[1].chordEvents = [try event("G7", fraction: 0.8, seed: 9)]
            _ = chart.setMeasureManualLayoutWidth(120, for: ids[0])
            _ = chart.setMeasureManualLayoutWidth(240, for: ids[1])
            XCTAssertTrue(chart.deleteCommittedChordBarline(after: ids[0], sourceMeasureWidths: [ids[0]: 200, ids[1]: 200]))
            XCTAssertEqual(try XCTUnwrap(chart.measures[0].chordEvents[0].manualVisualLaneFraction), 0.1, accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(chart.measures[0].chordEvents[1].manualVisualLaneFraction), 0.9, accuracy: 0.0001)
        }
    }

    func testRhythmDeletionRefusesMappedNotesTiesInkAndOrphanedRhythmMetadataAtomically() throws {
        for variant in 0..<6 {
            var chart = Chart.blank(title: "Rhythm merge guards", measureCount: 2, layoutStyle: .rhythmSectionSheet)
            let leftID = chart.measures[0].id
            switch variant {
            case 0:
                chart.systems[0].measures[1].rhythmMap = MeasureRhythmMap(values: [.half, .half], tieOutSlotIndices: [0])
            case 1:
                chart.systems[0].measures[1].pitchedNoteEvents = [LeadSheetPitchedNoteEvent(rhythmSlotIndex: 0,
                    staffPosition: LeadSheetStaffPosition(staffStep: 1))]
            case 2:
                chart.systems[0].measures[1].handwrittenRhythmicNotationData = drawing(at: CGPoint(x: 20, y: 20)).dataRepresentation()
            case 3:
                chart.systems[0].measures[1].handwrittenRhythmicNotationCoordinateSpace = .init(width: 200, height: 100)
            case 4:
                var chord = try event("F", fraction: 0.5, seed: 5)
                chord.mappedRhythmSlotIndex = 2
                chart.systems[0].measures[1].chordEvents = [chord]
            default:
                chart.freeInkArticulations = [FreeInkArticulation(kind: .accent,
                    measureID: chart.measures[1].id,
                    sourceInkData: drawing(at: CGPoint(x: 20, y: 20)).dataRepresentation(),
                    attachment: .staff(xFraction: 0.5, yFraction: 0.5))]
            }
            let original = chart
            XCTAssertFalse(chart.canDeleteCommittedChordBarline(after: leftID), "variant \(variant)")
            XCTAssertFalse(chart.deleteCommittedChordBarline(after: leftID), "variant \(variant)")
            XCTAssertEqual(chart, original)
        }
    }

    func testRhythmDeletionRefusesAuthoredRowBoundaryAndPreservesItsLayout() throws {
        var chart = Chart.blank(title: "Keep authored row", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let ids = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSystemBreak(before: ids[1]))
        let original = chart
        XCTAssertFalse(chart.canDeleteCommittedChordBarline(after: ids[0]))
        XCTAssertFalse(chart.deleteCommittedChordBarline(after: ids[0]))
        XCTAssertEqual(chart, original)
    }

    func testRhythmDeletionKeepsBoundaryWhenArchivedStaffInkUsesEitherMeasure() throws {
        for ownerIndex in [0, 1] {
            var chart = Chart.blank(title: "Keep staff writing", measureCount: 3, layoutStyle: .rhythmSectionSheet)
            let ids = chart.measures.map(\.id)
            let page = layout(chart)
            let frame = LeadSheetActiveInkScope.pageWritingFrame(for: page)
            let owner = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == ids[ownerIndex] })
            let archive = drawing(at: CGPoint(x: owner.staffFrame.midX - frame.minX,
                y: owner.staffFrame.midY - frame.minY)).dataRepresentation()
            chart.pageHandwrittenNotationData = archive
            chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: page, relativeTo: frame)
            let original = chart

            XCTAssertFalse(chart.canDeleteCommittedChordBarline(after: ids[0]))
            XCTAssertFalse(chart.deleteCommittedChordBarline(after: ids[0]))
            XCTAssertEqual(chart, original)
        }
    }

    func testRhythmDeletionPreservesUnrelatedStaffInkAndRetiresOnlyUnusedRegistrations() throws {
        var chart = Chart.blank(title: "Other measure ink", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let originalID = chart.measures[0].id
        let beforeSplit = layout(chart)
        let system = try XCTUnwrap(beforeSplit.systems.first)
        let measure = try XCTUnwrap(system.measures.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: beforeSplit.paperFrame(for: system)))
        var state = ChordPreviewState(layoutPageSize: size)
        state.replaceDraftBarlines(with: [DraftBarline(measureID: originalID, measureIndex: 1,
            fraction: 0.5, laneLocation: .init(systemIndex: system.index,
                fraction: Double((measure.staffFrame.midX - lane.minX) / lane.width)),
            layoutPageSize: size, metrics: .init(height: 54, width: 2,
                angleDegreesFromVertical: 1, straightness: 0.98, laneCoverage: 0.9))])
        XCTAssertEqual(chart.commitChordInkDraftBatch(state).renderedBarlineCount, 1)
        let ids = chart.measures.map(\.id)
        let page = layout(chart)
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: page)
        let owner = try XCTUnwrap(page.systems.flatMap(\.measures).first { $0.sourceMeasureID == ids[2] })
        let archive = drawing(at: CGPoint(x: owner.staffFrame.midX - frame.minX,
            y: owner.staffFrame.midY - frame.minY)).dataRepresentation()
        chart.pageHandwrittenNotationData = archive
        chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: page, relativeTo: frame)
        let surviving = chart.pageHandwrittenNotationCoordinateSpace?.measureAnchors?.first { $0.measureID == ids[2] }

        XCTAssertTrue(chart.canDeleteCommittedChordBarline(after: ids[0]))
        XCTAssertTrue(chart.deleteCommittedChordBarline(after: ids[0]))
        let reopened = try reopen(chart)
        XCTAssertEqual(reopened.pageHandwrittenNotationData, archive)
        XCTAssertEqual(reopened.pageHandwrittenNotationCoordinateSpace?.measureAnchors, surviving.map { [$0] })
        XCTAssertFalse(reopened.pageHandwrittenNotationCoordinateSpace?.chordAnchors?.contains {
            $0.measureID == ids[0] || $0.measureID == ids[1]
        } ?? false)
    }

    func testRhythmDeletionRefusesUnknownInkGeometryWithoutChangingArchive() throws {
        for data in [Data([1, 2, 3]), drawing(at: CGPoint(x: 20, y: 20)).dataRepresentation()] {
            var chart = Chart.blank(title: "Unknown source", measureCount: 2, layoutStyle: .rhythmSectionSheet)
            let id = chart.measures[0].id
            chart.pageHandwrittenNotationData = data
            let original = chart
            XCTAssertFalse(chart.canDeleteCommittedChordBarline(after: id))
            XCTAssertFalse(chart.deleteCommittedChordBarline(after: id))
            XCTAssertEqual(chart, original)
        }
    }

    func testGenericDeletionPreservesFollowingMeterReceiptAndRepeatArchiveInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = Chart.blank(title: "Merge before change", measureCount: 3, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            _ = chart.applyMeterChange(Meter(numerator: 3, denominator: 4), after: ids[1], scope: .toEndOfPiece)
            let change = try XCTUnwrap(chart.timeSignatureChanges.first)
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[1]))
            let archive = drawing(at: CGPoint(x: 20, y: 20)).dataRepresentation()
            let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == repeatID })
            chart.roadmapObjects[index].sourceInkData = archive

            XCTAssertTrue(chart.deleteCommittedChordBarline(after: ids[0]))
            let reopened = try reopen(chart)
            XCTAssertEqual(reopened.measures.map(\.id), [ids[0], ids[2]])
            XCTAssertEqual(reopened.timeSignatureChanges.first?.id, change.id)
            XCTAssertEqual(reopened.timeSignatureChanges.first?.afterMeasureID, ids[0])
            XCTAssertEqual(reopened.measures[0].resolvedMeter(defaultMeter: reopened.defaultMeter), Meter(numerator: 4, denominator: 4))
            XCTAssertEqual(reopened.measures[1].resolvedMeter(defaultMeter: reopened.defaultMeter), Meter(numerator: 3, denominator: 4))
            let span = try XCTUnwrap(reopened.roadmapObject(id: repeatID))
            XCTAssertEqual(span.startMeasureID, ids[0])
            XCTAssertEqual(span.endMeasureID, ids[0])
            XCTAssertEqual(span.sourceInkData, archive)
        }
    }

    func testGenericDeletionKeepsKeyMeterAndNonSingleBoundariesInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for variant in 0..<3 {
                var chart = Chart.blank(title: "Keep semantic boundary", measureCount: 2, layoutStyle: style)
                let ids = chart.measures.map(\.id)
                if variant == 0 { _ = chart.setKeyChange(.dMajor, atStartOf: ids[1]) }
                else if variant == 1 {
                    _ = chart.applyMeterChange(Meter(numerator: 3, denominator: 4), after: ids[0], scope: .toEndOfPiece)
                } else { chart.systems[0].measures[0].barlineAfter = .double }
                let original = chart
                XCTAssertFalse(chart.canDeleteCommittedChordBarline(after: ids[0]))
                XCTAssertFalse(chart.deleteCommittedChordBarline(after: ids[0]))
                XCTAssertEqual(chart, original)
            }
        }
    }

    private func event(_ text: String, fraction: Double, seed: Int) throws -> ChordEvent {
        ChordEvent(id: UUID(), symbol: try ChordSymbolParser.parse(text), spellingIntent: .explicit,
            startPosition: BeatPosition(beat: 3, subdivision: 0, subdivisionsPerBeat: 1),
            duration: .half, rhythmPlacement: .inline, tieOut: true, hitStyle: .accent,
            rawInput: text, sourceInkData: drawing(at: CGPoint(x: CGFloat(seed) * 4 + 10, y: 10)).dataRepresentation(),
            sourceCandidateSignature: [text], sourceRecognitionPipelineVersion: "deletion-test",
            manualDisplayWidth: 55, manualHorizontalScale: 0.8,
            manualLaneFraction: fraction, manualVisualLaneFraction: fraction)
    }

    private func assertReceipt(_ actual: ChordEvent, matches original: ChordEvent,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, original.id, file: file, line: line)
        XCTAssertEqual(actual.symbol, original.symbol, file: file, line: line)
        XCTAssertEqual(actual.sourceInkData, original.sourceInkData, file: file, line: line)
        XCTAssertEqual(actual.sourceCandidateSignature, original.sourceCandidateSignature, file: file, line: line)
        XCTAssertEqual(actual.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion, file: file, line: line)
        XCTAssertEqual(actual.rawInput, original.rawInput, file: file, line: line)
        XCTAssertEqual(actual.duration, original.duration, file: file, line: line)
        XCTAssertEqual(actual.tieOut, original.tieOut, file: file, line: line)
        XCTAssertEqual(actual.hitStyle, original.hitStyle, file: file, line: line)
        XCTAssertEqual(actual.rhythmPlacement, original.rhythmPlacement, file: file, line: line)
        XCTAssertEqual(actual.spellingIntent, original.spellingIntent, file: file, line: line)
        XCTAssertEqual(actual.spellingOverrideSource, original.spellingOverrideSource, file: file, line: line)
        XCTAssertEqual(actual.manualDisplayWidth, original.manualDisplayWidth, file: file, line: line)
        XCTAssertEqual(actual.manualHorizontalScale, original.manualHorizontalScale, file: file, line: line)
    }

    private func drawing(at point: CGPoint) -> PKDrawing {
        let points = [point, CGPoint(x: point.x + 4, y: point.y - 8), CGPoint(x: point.x + 8, y: point.y)]
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points.enumerated().map { index, value in
                PKStrokePoint(location: value, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 200)))])
    }

    private func layout(_ chart: Chart) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        try repository.saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        return try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
    }
}
#endif

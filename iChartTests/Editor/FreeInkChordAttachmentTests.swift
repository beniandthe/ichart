#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

@MainActor
final class FreeInkChordAttachmentTests: XCTestCase {
    func testInkDirectlyBelowDraggedChordKeepsItsOffsetAfterReopenInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            var chart = Chart.blank(title: "Chord Ink Attachment", measureCount: 4, layoutStyle: style)
            let measureIDs = chart.measures.map(\.id)
            let firstID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                ChordSymbolParser.parse("Cmaj7"), rawInput: "Cmaj7", to: measureIDs[0], atFraction: 0
            ))
            let secondID = try XCTUnwrap(chart.appendRecognizedChordEvent(
                ChordSymbolParser.parse("D7"), rawInput: "D7", to: measureIDs[1], atFraction: 0
            ))
            let source = try coordinateSpace(for: chart)
            let firstFrame = try chordFrame(firstID, in: source)
            let secondFrame = try chordFrame(secondID, in: source)
            let firstStaff = source.measureAnchors?.first { $0.measureID == measureIDs[0] }?.staffFrame?.rect
            let x = firstFrame.midX
            let y = firstStaff.map { $0.maxY + 15 } ?? (firstFrame.maxY + 8)
            let ink = PKDrawing(strokes: [
                stroke([CGPoint(x: x - 5, y: y), CGPoint(x: x + 4, y: y + 5)], seed: 11),
                stroke([CGPoint(x: x + 4, y: y + 5), CGPoint(x: x + 6, y: y + 1)], seed: 12),
                stroke([CGPoint(x: secondFrame.midX, y: secondFrame.maxY + 8),
                        CGPoint(x: secondFrame.midX + 5, y: secondFrame.maxY + 13)], seed: 21),
                stroke([CGPoint(x: x, y: 900), CGPoint(x: x + 11, y: 906)], seed: 31)
            ])
            let originalBytes = ink.dataRepresentation()
            chart.pageHandwrittenNotationData = originalBytes
            chart.pageHandwrittenNotationCoordinateSpace = source

            var renamed = chart
            renamed.title = "Renamed Chart"
            let renamedSpace = try coordinateSpace(for: renamed)
            let withRenamedTitle = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(ink,
                sourceCoordinateSpace: source, targetCoordinateSpace: renamedSpace)
            assertProjection(withRenamedTitle, of: ink, from: firstFrame, to: firstFrame)

            var resized = chart
            XCTAssertNotNil(resized.setChordEventManualHorizontalScale(0.75, for: firstID))
            let resizedSpace = try coordinateSpace(for: resized)
            let resizedFrame = try chordFrame(firstID, in: resizedSpace)
            XCTAssertNotEqual(resizedFrame.width, firstFrame.width, style.rawValue)
            let withResizedChord = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(ink,
                sourceCoordinateSpace: source, targetCoordinateSpace: resizedSpace)
            assertProjection(withResizedChord, of: ink, from: firstFrame, to: firstFrame)

            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(firstID, to: measureIDs[0],
                atFraction: 0.55, visualFraction: 0.55, preserveMusicalPlacement: true))
            let moved = try coordinateSpace(for: chart)
            let movedFrame = try chordFrame(firstID, in: moved)
            XCTAssertGreaterThan(abs(movedFrame.minX - firstFrame.minX), 10, style.rawValue)
            assertProjection(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(ink,
                sourceCoordinateSpace: source, targetCoordinateSpace: moved),
                of: ink, from: firstFrame, to: movedFrame)

            XCTAssertTrue(chart.moveChordEventInCommittedChordLane(firstID, to: measureIDs[2],
                atFraction: 0.25, visualFraction: 0.25, preserveMusicalPlacement: true))
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
            XCTAssertEqual(reopened.pageHandwrittenNotationData, originalBytes)
            XCTAssertEqual(reopened.pageHandwrittenNotationCoordinateSpace, source)
            let destination = try coordinateSpace(for: reopened)
            let finalFrame = try chordFrame(firstID, in: destination)
            let restored = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
                from: reopened.pageHandwrittenNotationData,
                sourceCoordinateSpace: reopened.pageHandwrittenNotationCoordinateSpace,
                targetCoordinateSpace: destination))
            assertProjection(restored, of: ink, from: firstFrame, to: finalFrame)
        }
    }

    func testTightRowsUseTheNearestChordAboveInkAndRejectInkOverTheNextChord() throws {
        let upperMeasure = UUID()
        let lowerMeasure = UUID()
        let upperChord = UUID()
        let lowerChord = UUID()
        let upperFrame = CGRect(x: 82, y: 40, width: 20, height: 20)
        let lowerFrame = CGRect(x: 82, y: 101, width: 20, height: 16)
        let upperStaff = try XCTUnwrap(PersistentInkMeasureAnchor(measureID: upperMeasure,
            frame: CGRect(x: 60, y: 40, width: 150, height: 20),
            staffFrame: CGRect(x: 60, y: 60, width: 150, height: 44)))
        let source = PersistentInkCoordinateSpace(width: 320, height: 300, measureAnchors: [upperStaff], chordAnchors: [
            try XCTUnwrap(PersistentInkChordAnchor(measureID: upperMeasure, chordID: upperChord, frame: upperFrame)),
            try XCTUnwrap(PersistentInkChordAnchor(measureID: lowerMeasure, chordID: lowerChord, frame: lowerFrame))
        ])
        var target = source
        target.chordAnchors = [
            try XCTUnwrap(PersistentInkChordAnchor(measureID: upperMeasure, chordID: upperChord,
                frame: upperFrame.offsetBy(dx: 40, dy: 0))),
            try XCTUnwrap(PersistentInkChordAnchor(measureID: lowerMeasure, chordID: lowerChord,
                frame: lowerFrame.offsetBy(dx: 20, dy: 0)))
        ]
        let policy = LeadSheetFreeInkChordAttachmentPolicy(source: source, target: target)
        XCTAssertNil(policy.transform(for: CGRect(x: 89, y: 104, width: 6, height: 5)))
        XCTAssertEqual(policy.transform(for: CGRect(x: 89, y: 119, width: 6, height: 5)),
            CGAffineTransform(translationX: 20, y: 0))
    }

    func testStationaryLeadingChordDoesNotLeaveStaffInkAcrossShortenedBarline() throws {
        var chart = Chart.blank(title: "Stationary chord resize", key: .cMajor,
            measureCount: 20, layoutStyle: .rhythmSectionSheet)
        let ids = chart.measures.map(\.id)
        let firstID = try XCTUnwrap(ids.first)
        chart.setMeasureManualLayoutWidth(240, for: firstID)
        let text = "C7(b9)(#5)"
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(
            ChordSymbolParser.parse(text), rawInput: text, to: firstID, atFraction: 0))
        XCTAssertTrue(chart.moveChordEventInCommittedChordLane(chordID, to: firstID,
            atFraction: 0, visualFraction: 0, preserveMusicalPlacement: true))

        let pageSize = CGSize(width: 990, height: 1_200)
        func space(for chart: Chart) throws -> PersistentInkCoordinateSpace {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            return try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: layout, relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: layout)))
        }
        func staff(in space: PersistentInkCoordinateSpace) throws -> CGRect {
            try XCTUnwrap(space.measureAnchors?.first { $0.measureID == firstID }?.staffFrame).rect
        }
        let source = try space(for: chart)
        let oldStaff = try staff(in: source)
        let before = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let firstRow = try XCTUnwrap(before.systems.first)
        let availableBody = LeadSheetPageLayoutEngine.rhythmSectionAvailableRowWidth(for: firstRow, in: before)
        var resized = chart
        XCTAssertTrue(resized.fitRhythmMeasureRows([ids], availableWidths: [availableBody]))
        let target = try space(for: resized)
        let newStaff = try staff(in: target)
        let chord = try XCTUnwrap(source.chordAnchors?.first { $0.chordID == chordID })
        XCTAssertEqual(target.chordAnchors?.first { $0.chordID == chordID }, chord,
            "The leading chord must remain stationary through fitted-row compression")
        let frame = chord.frame.rect
        let startX = max(newStaff.maxX + 5, frame.minX + 5)
        let endX = min(frame.maxX - 5, oldStaff.maxX - 5)
        XCTAssertGreaterThan(endX, startX, "A long leading glyph must overhang the compressed staff")
        let x = (startX + endX) / 2
        let y = max(oldStaff.midY, frame.maxY + 6)
        XCTAssertLessThan(y + 4, oldStaff.maxY, "The stroke must be on the original staff")
        let sourceStroke = stroke([CGPoint(x: x, y: y), CGPoint(x: x + 2, y: y + 2)], seed: 51)
        let sourceDrawing = PKDrawing(strokes: [sourceStroke])
        XCTAssertTrue(oldStaff.contains(sourceStroke.renderBounds))
        XCTAssertGreaterThan(sourceStroke.renderBounds.minX, newStaff.maxX)
        let projected = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(sourceDrawing,
            sourceCoordinateSpace: source, targetCoordinateSpace: target)
        let projectedStroke = try XCTUnwrap(projected.strokes.first)
        XCTAssertTrue(newStaff.contains(projectedStroke.renderBounds),
            "Staff ink must stay with its measure when a neighboring barline moves under a stationary chord")
        let projectedPoint = try XCTUnwrap(projectedStroke.path.first).location.applying(projectedStroke.transform)
        XCTAssertEqual((projectedPoint.x - newStaff.minX) / newStaff.width,
            (x - oldStaff.minX) / oldStaff.width, accuracy: 0.002)
    }

    private func coordinateSpace(for chart: Chart) throws -> PersistentInkCoordinateSpace {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 900, height: 1_200))
        return try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: layout, relativeTo: LeadSheetActiveInkScope.pageWritingFrame(for: layout)))
    }

    private func chordFrame(_ id: UUID, in space: PersistentInkCoordinateSpace) throws -> CGRect {
        try XCTUnwrap(space.chordAnchors?.first { $0.chordID == id }).frame.rect
    }

    private func assertProjection(_ projected: PKDrawing, of original: PKDrawing,
        from source: CGRect, to target: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(projected.strokes.map(\.randomSeed), original.strokes.map(\.randomSeed),
            file: file, line: line)
        for (index, pair) in zip(original.strokes, projected.strokes).enumerated() {
            let expectedDX = index < 2 ? target.minX - source.minX : 0
            let expectedDY = index < 2 ? target.minY - source.minY : 0
            let (before, after) = pair
            XCTAssertEqual(after.path.count, before.path.count, file: file, line: line)
            for (start, end) in zip(before.path, after.path) {
                let old = start.location.applying(before.transform)
                let new = end.location.applying(after.transform)
                XCTAssertEqual(new.x - old.x, expectedDX, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(new.y - old.y, expectedDY, accuracy: 0.01, file: file, line: line)
            }
        }
    }

    private func stroke(_ locations: [CGPoint], seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.03,
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1,
                azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }
}
#endif

import CoreGraphics
import XCTest
@testable import iChart
#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
#endif

final class PaperMeasureAttachmentSafetyTests: XCTestCase {
    func testAdoptingPackedLegacyRowsCreatesUniqueSystemsAndRetainsSectionOwnership() throws {
        var chart = Chart.blank(title: "Packed legacy rows", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertEqual(chart.systems.count, 1)
        let section = SectionLabel(id: UUID(), text: "Last section", type: .sectionName,
            anchorMeasureID: measureIDs[7], anchorSystemID: chart.systems[0].id, rawInput: "Last section")
        chart.sectionLabels = [section]
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart, pageSize: CGSize(width: 900, height: 1400))
        let rows = try layout.systems.compactMap { system -> [UUID: ClosedRange<Double>]? in
            let measures = system.measures.filter { $0.sourceMeasureID != nil }
            guard !measures.isEmpty else { return nil }
            let axis = try XCTUnwrap(system.paperMeasurePositioningFrame(in: layout.paperFrame(for: system)))
            return Dictionary(uniqueKeysWithValues: measures.map { measure in
                let start = max(0, min(1, Double((measure.staffFrame.minX - axis.minX) / axis.width)))
                let end = max(start, min(1, Double((measure.staffFrame.maxX - axis.minX) / axis.width)))
                return (measure.sourceMeasureID!, start...end)
            })
        }
        XCTAssertGreaterThan(rows.count, 1, "The fixture must exercise multiple displayed rows from one stored system")

        XCTAssertTrue(chart.adoptPaperMeasureLayout(rows))

        XCTAssertEqual(Set(chart.systems.map(\.id)).count, chart.systems.count)
        XCTAssertEqual(chart.measures.map(\.id), measureIDs)
        let owner = try XCTUnwrap(chart.systems.first { $0.measures.contains { $0.id == section.anchorMeasureID } })
        XCTAssertEqual(chart.sectionLabels.first?.id, section.id)
        XCTAssertEqual(chart.sectionLabels.first?.anchorSystemID, owner.id)
        XCTAssertEqual(try reopened(chart), chart)
    }

    func testOpenAnnotationOwnersSurviveFinishingMovingAndResizingInBothStyles() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            for attachment in ExternalAttachment.allCases {
                for operation in PaperOperation.allCases {
                    var chart = try splitPaperRow(style)
                    let firstID = chart.systems[0].measures[0].id
                    let peerID = chart.systems[0].measures[1].id
                    try attach(attachment, to: peerID, in: &chart)
                    let marks = chart.freeInkArticulations
                    let symbols = chart.freehandSymbols
                    let labels = chart.sectionLabels
                    let cues = chart.cueTexts

                    try apply(operation, to: firstID, in: &chart)

                    let context = "\(style) \(attachment) \(operation)"
                    XCTAssertNotNil(chart.measure(id: peerID), context)
                    XCTAssertEqual(chart.freeInkArticulations, marks, context)
                    XCTAssertEqual(chart.freehandSymbols, symbols, context)
                    XCTAssertEqual(chart.sectionLabels, labels, context)
                    XCTAssertEqual(chart.cueTexts, cues, context)
                    if attachment != .freehandSymbol {
                        XCTAssertEqual(try reopened(chart), chart, context)
                    }
                }
            }
        }
    }

    func testReorderingKeepsEndingAndRepeatRangesOrderedAndVisible() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            var chart = Chart.blank(title: "Reordered ranges", measureCount: 4, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let row = Dictionary(uniqueKeysWithValues: ids.enumerated().map {
                ($0.element, Double($0.offset) / 4...Double($0.offset + 1) / 4)
            })
            XCTAssertTrue(chart.adoptPaperMeasureLayout([row]))
            let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[0], endMeasureID: ids[1]))
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[0], endMeasureID: ids[2]))
            let originalEndpoints = Dictionary(uniqueKeysWithValues: chart.roadmapObjects.map {
                ($0.id, Set([$0.startMeasureID, $0.endMeasureID!]))
            })

            XCTAssertTrue(chart.movePaperMeasure(ids[0], toStartFraction: 0.75))
            chart = try reopened(chart)

            XCTAssertEqual(Set(chart.measures.map(\.id)), Set(ids))
            for object in chart.roadmapObjects {
                let start = try XCTUnwrap(chart.measures.firstIndex { $0.id == object.startMeasureID })
                let endID = try XCTUnwrap(object.endMeasureID)
                let end = try XCTUnwrap(chart.measures.firstIndex { $0.id == endID })
                XCTAssertLessThanOrEqual(start, end, "Reordering must keep the saved range renderable")
                XCTAssertEqual(Set([object.startMeasureID, endID]), originalEndpoints[object.id])
                XCTAssertTrue(chart.measure(id: object.startMeasureID)?.roadmapObjectIDs.contains(object.id) == true)
                XCTAssertTrue(chart.measure(id: endID)?.roadmapObjectIDs.contains(object.id) == true)
                let system = try XCTUnwrap(chart.systems.first { $0.measures.contains { $0.id == object.startMeasureID } })
                XCTAssertEqual(object.anchorSystemID, system.id)
            }
            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: chart, pageSize: CGSize(width: 900, height: 1400))
            XCTAssertTrue(layout.systems.flatMap(\.endingLayouts).contains { $0.roadmapObjectID == endingID })
            let markers = layout.systems.flatMap(\.measures).flatMap(\.repeatMarkerLayouts)
                .filter { $0.roadmapObjectID == repeatID }
            XCTAssertEqual(markers.filter { $0.edge == .leading }.count, 1)
            XCTAssertEqual(markers.filter { $0.edge == .trailing }.count, 1)
        }
    }

    func testPaperRhythmCueDoesNotBlockAHandwrittenBoundaryAndKeepsItsOwner() throws {
        var chart = Chart.blank(title: "Cue before measures", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 1))
        let originalID = chart.systems[0].measures[0].id
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0, kind: .double))
        let cueID = try XCTUnwrap(chart.addCueText("Enter here", anchorMeasureID: originalID, atFraction: 0.75))

        let rightID = try XCTUnwrap(chart.placePaperBarline(inRow: 0, at: 0.5, kind: .single))
        let cue = try XCTUnwrap(chart.cueTexts.first { $0.id == cueID })

        XCTAssertNotEqual(rightID, originalID)
        XCTAssertEqual(cue.anchorMeasureID, rightID)
        XCTAssertEqual(cue.text, "Enter here")
        XCTAssertTrue(chart.measure(id: rightID)?.cueTextIDs.contains(cueID) == true)
        XCTAssertFalse(chart.measure(id: originalID)?.cueTextIDs.contains(cueID) == true)
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.95, kind: .double))
        XCTAssertTrue(chart.finishPaperWritingRows())
        XCTAssertEqual(chart.cueTexts.first { $0.id == cueID }?.anchorMeasureID, rightID)
        XCTAssertEqual(try reopened(chart), chart)
    }

    #if canImport(UIKit) && canImport(PencilKit)
    func testOpenPageInkOwnerAndArchiveSurviveFinishingMovingAndResizing() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            for operation in PaperOperation.allCases {
                var chart = try splitPaperRow(style)
                let firstID = chart.systems[0].measures[0].id
                let peerID = chart.systems[0].measures[1].id
                let bounds = CGRect(x: 300, y: 200, width: 400, height: 100)
                let anchor = try XCTUnwrap(PersistentInkMeasureAnchor(measureID: peerID, frame: bounds))
                let coordinateSpace = PersistentInkCoordinateSpace(width: 900, height: 1400, measureAnchors: [anchor])
                let points = [CGPoint(x: 400, y: 240), CGPoint(x: 430, y: 260)]
                let path = PKStrokePath(controlPoints: points.enumerated().map { index, point in
                    PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                        size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                }, creationDate: .now)
                let drawing = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
                    path: path, transform: .identity, mask: nil, randomSeed: 41)])
                let data = drawing.dataRepresentation()
                chart.setPageHandwrittenNotationDrawing(data, coordinateSpace: coordinateSpace)
                let savedData = try XCTUnwrap(chart.pageHandwrittenNotationData)

                try apply(operation, to: firstID, in: &chart)

                XCTAssertNotNil(chart.measure(id: peerID), "\(style) \(operation)")
                XCTAssertEqual(chart.pageHandwrittenNotationData, savedData)
                XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, coordinateSpace)
                XCTAssertEqual(try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenNotationData)).strokes.count, 1)
                XCTAssertEqual(try reopened(chart), chart)
            }
        }
    }
    #endif

    private enum ExternalAttachment: CaseIterable {
        case articulation
        case freehandSymbol
        case section
        case cue
    }

    private enum PaperOperation: CaseIterable {
        case finish
        case move
        case resize
    }

    private func splitPaperRow(_ style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Open annotation owner", measureCount: 1, layoutStyle: style)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 1))
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0, kind: .double))
        XCTAssertNotNil(chart.placePaperBarline(inRow: 0, at: 0.35, kind: .single))
        XCTAssertEqual(chart.systems[0].measures.count, 2)
        XCTAssertEqual(chart.systems[0].measures[1].authoringState, .open)
        return chart
    }

    private func attach(_ attachment: ExternalAttachment, to measureID: UUID, in chart: inout Chart) throws {
        switch attachment {
        case .articulation:
            chart.freeInkArticulations = [FreeInkArticulation(kind: .fermata,
                measureID: measureID, sourceInkData: Data([1, 2, 3]),
                attachment: .staff(xFraction: 0.5, yFraction: 0.5))]
        case .freehandSymbol:
            chart.freehandSymbols = [FreehandSymbol(id: UUID(), anchorMeasureID: measureID,
                lane: .aboveMeasure, normalizedFrame: .init(x: 0.5, y: 0.5, width: 0.1, height: 0.2),
                drawingData: Data([3, 2, 1]), zIndex: 0)]
        case .section:
            let systemID = try XCTUnwrap(chart.systems.first { $0.measures.contains { $0.id == measureID } }?.id)
            chart.sectionLabels = [SectionLabel(id: UUID(), text: "Bridge", type: .sectionName,
                anchorMeasureID: measureID, anchorSystemID: systemID, rawInput: "Bridge")]
        case .cue:
            XCTAssertNotNil(chart.addCueText("Stay with this measure", anchorMeasureID: measureID))
        }
    }

    private func apply(_ operation: PaperOperation, to measureID: UUID, in chart: inout Chart) throws {
        switch operation {
        case .finish:
            XCTAssertTrue(chart.finishPaperWritingRows())
        case .move:
            XCTAssertTrue(chart.movePaperMeasure(measureID, toStartFraction: 0.55))
        case .resize:
            XCTAssertTrue(chart.resizePaperMeasure(measureID, startFraction: 0, endFraction: 0.25))
        }
    }

    private func reopened(_ chart: Chart) throws -> Chart {
        try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(chart))
    }
}

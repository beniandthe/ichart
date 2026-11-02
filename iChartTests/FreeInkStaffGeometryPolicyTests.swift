import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class FreeInkStaffGeometryPolicyTests: XCTestCase {
    func testLegacyCoordinateMetadataDecodesWithoutStaffOrEngravingFields() throws {
        let measureID = UUID()
        let legacy = """
        {"width":700,"height":1020,"measureAnchors":[
          {"measureID":"\(measureID.uuidString)","frame":{"x":24,"y":150,"width":200,"height":78}}
        ]}
        """
        let decoded = try JSONDecoder().decode(PersistentInkCoordinateSpace.self, from: Data(legacy.utf8))

        XCTAssertNil(decoded.engravingPreset)
        XCTAssertNil(decoded.measureAnchors?.first?.staffFrame)
        XCTAssertEqual(decoded.measureAnchors?.first?.measureID, measureID)
        XCTAssertEqual(decoded.width, 700)
        XCTAssertEqual(decoded.height, 1020)
        XCTAssertEqual(try roundTrip(decoded), decoded)
    }

    func testOptionalStaffAndEngravingMetadataRoundTripsThroughBothInitializers() throws {
        let anchor = try XCTUnwrap(PersistentInkMeasureAnchor(
            measureID: UUID(),
            frame: CGRect(x: 30, y: 150, width: 240, height: 78),
            staffFrame: CGRect(x: 28, y: 206, width: 244, height: 44.8)
        ))
        let spaces = [
            PersistentInkCoordinateSpace(
                width: 700, height: 1020, measureAnchors: [anchor], engravingPreset: .wide
            ),
            try XCTUnwrap(PersistentInkCoordinateSpace(
                size: CGSize(width: 700, height: 1020),
                measureAnchors: [anchor], engravingPreset: .bold
            ))
        ]
        for space in spaces {
            XCTAssertEqual(try roundTrip(space), space)
            XCTAssertEqual(space.measureAnchors?.first?.staffFrame?.rect, anchor.staffFrame?.rect)
        }
    }

    func testRichAuthoredMetadataRemainsUnchangedAcrossOtherLayoutChanges() throws {
        let sourceChart = makeChart(preset: .wide)
        let source = try coordinateSpace(for: sourceChart, width: 932, rich: true)
        var changedChart = sourceChart
        changedChart.engravingPreset = .compact
        changedChart.staffSystemDensity = .dense

        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(source, chart: changedChart),
            source
        )
    }

    func testLegacyExactFramesRecoverAuthoredStaffAcrossEngravingChangesWithoutEditingChart() throws {
        for style in [ChartLayoutStyle.leadSheet, .rhythmSectionSheet] {
            for preset in [EngravingPreset.wide, .bold] {
                for width in [CGFloat(800), CGFloat(1200)] {
                    var sourceChart = makeChart(preset: preset, style: style)
                    let legacy = try coordinateSpace(for: sourceChart, width: width, rich: false)
                    let expected = try coordinateSpace(for: sourceChart, width: width, rich: true)
                    sourceChart.pageHandwrittenNotationData = Data([7, 11, 19])
                    sourceChart.pageHandwrittenNotationCoordinateSpace = legacy
                    sourceChart.engravingPreset = .compact
                    let unchangedChart = sourceChart

                    let recovered = try XCTUnwrap(
                        LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(legacy, chart: sourceChart)
                    )

                    XCTAssertEqual(recovered.engravingPreset, preset)
                    XCTAssertEqual(recovered.measureAnchors, expected.measureAnchors)
                    XCTAssertEqual(recovered.width, legacy.width)
                    XCTAssertEqual(recovered.height, legacy.height)
                    XCTAssertEqual(recovered.chordAnchors, legacy.chordAnchors)
                    XCTAssertEqual(sourceChart, unchangedChart)
                    XCTAssertEqual(sourceChart.pageHandwrittenNotationData, Data([7, 11, 19]))
                    XCTAssertEqual(sourceChart.pageHandwrittenNotationCoordinateSpace, legacy)
                }
            }
        }
    }

    func testLegacyCurrentEngravingKeepsOriginalMetadata() throws {
        let chart = makeChart(preset: .wide)
        let legacy = try coordinateSpace(for: chart, width: 932, rich: false)

        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(legacy, chart: chart), legacy
        )
    }

    func testOneNonmatchingSavedAnchorPreventsPartialLayoutRecovery() throws {
        var chart = makeChart(preset: .wide)
        var legacy = try coordinateSpace(for: chart, width: 932, rich: false)
        var anchors = try XCTUnwrap(legacy.measureAnchors)
        XCTAssertGreaterThan(anchors.count, 1)
        anchors[anchors.count - 1].frame.y += 0.1
        legacy.measureAnchors = anchors
        chart.engravingPreset = .compact

        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(legacy, chart: chart), legacy
        )
    }

    func testConflictingAuthoredPresetOrPartialStaffEvidenceDoesNotGuess() throws {
        var chart = makeChart(preset: .wide)
        let legacy = try coordinateSpace(for: chart, width: 932, rich: false)
        chart.engravingPreset = .compact
        var conflictingPreset = legacy
        conflictingPreset.engravingPreset = .bold

        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(conflictingPreset, chart: chart),
            conflictingPreset
        )

        var conflictingStaff = legacy
        var anchors = try XCTUnwrap(conflictingStaff.measureAnchors)
        anchors[0].staffFrame = try XCTUnwrap(PersistentInkFrame(
            rect: CGRect(x: 1, y: 2, width: 300, height: 42)
        ))
        conflictingStaff.measureAnchors = anchors
        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(conflictingStaff, chart: chart),
            conflictingStaff
        )
    }

    func testMissingAuthoredLayoutEvidenceKeepsUnanchoredSpaceUnchanged() throws {
        let chart = makeChart(preset: .compact)
        let unknownSource = PersistentInkCoordinateSpace(width: 700, height: 1020)
        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(unknownSource, chart: chart),
            unknownSource
        )
        XCTAssertNil(LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(nil, chart: chart))
    }

    func testSimpleChordSheetDoesNotInventStaffGeometry() throws {
        var chart = makeChart(preset: .wide, style: .simpleChordSheet)
        let legacy = try coordinateSpace(for: chart, width: 932, rich: false)
        chart.engravingPreset = .compact
        XCTAssertEqual(
            LeadSheetFreeInkStaffGeometryPolicy.sourceCoordinateSpace(legacy, chart: chart), legacy
        )
    }

    func testWideToCompactReflowsAutomaticStaffRowsWhilePreservingMeasureOrder() {
        for style in [ChartLayoutStyle.leadSheet, .rhythmSectionSheet] {
            for count in [1, 4, 8, 16] {
                for width in [CGFloat(800), CGFloat(1200)] {
                    var chart = Chart.blank(title: "Automatic staff packing", measureCount: count, layoutStyle: style)
                    chart.engravingPreset = .wide
                    let source = rowMembership(for: chart, width: width)
                    chart.engravingPreset = .compact
                    let target = rowMembership(for: chart, width: width)
                    let context = "\(style.rawValue), \(count) measures, canvas \(width)"

                    XCTAssertEqual(source.flatMap { $0 }, chart.measures.map(\.id), context)
                    XCTAssertEqual(target.flatMap { $0 }, chart.measures.map(\.id), context)
                    let expectsReflow = count >= 8 || (count == 4 && width == 800)
                    if expectsReflow {
                        XCTAssertNotEqual(source, target, context)
                    } else {
                        XCTAssertEqual(source, target, context)
                    }

                    if style == .rhythmSectionSheet, count == 8, width == 800 {
                        XCTAssertEqual(source.map(\.count), [3, 3, 2], context)
                        XCTAssertEqual(target.map(\.count), [4, 4], context)
                        // The original second row crosses two destination rows.
                        let destinationRows = Set(source[1].compactMap { measureID in
                            target.firstIndex { $0.contains(measureID) }
                        })
                        XCTAssertEqual(destinationRows, Set([0, 1]), context)
                    }
                }
            }
        }
    }

    private func rowMembership(for chart: Chart, width: CGFloat) -> [[UUID]] {
        LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: width, height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight)
        ).systems.map { $0.measures.compactMap(\.sourceMeasureID) }
    }

    private func makeChart(
        preset: EngravingPreset,
        style: ChartLayoutStyle = .rhythmSectionSheet
    ) -> Chart {
        var chart = Chart.blank(title: "Authored staff geometry", measureCount: 6, layoutStyle: style)
        chart.engravingPreset = preset
        chart.systems = chart.measures.enumerated().map { index, measure in
            ChartSystem(
                id: UUID(), index: index, spacingMode: .automatic,
                lineBreakRule: .forced, measures: [measure]
            )
        }
        return chart
    }

    private func coordinateSpace(
        for chart: Chart,
        width: CGFloat,
        rich: Bool
    ) throws -> PersistentInkCoordinateSpace {
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: width, height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight)
        )
        XCTAssertEqual(layout.engravingPreset, chart.engravingPreset)
        let inset = LeadSheetPageLayoutEngine.pageInkWritingInset
        let writingFrame = layout.paperEnvelope.insetBy(dx: inset, dy: inset)
        let anchors = layout.systems.flatMap { system in
            system.measures.compactMap { measure -> PersistentInkMeasureAnchor? in
                guard let measureID = measure.sourceMeasureID else { return nil }
                return PersistentInkMeasureAnchor(
                    measureID: measureID,
                    frame: measure.chordWritingFrame.offsetBy(
                        dx: -writingFrame.minX, dy: -writingFrame.minY
                    ),
                    staffFrame: rich && system.staffLineYPositions.count == 5
                        ? measure.staffFrame.insetBy(dx: 0, dy: 2).offsetBy(
                            dx: -writingFrame.minX, dy: -writingFrame.minY
                        ) : nil
                )
            }
        }
        return try XCTUnwrap(PersistentInkCoordinateSpace(
            size: writingFrame.size,
            measureAnchors: anchors,
            engravingPreset: rich ? chart.engravingPreset : nil
        ))
    }

    private func roundTrip(_ space: PersistentInkCoordinateSpace) throws -> PersistentInkCoordinateSpace {
        try JSONDecoder().decode(PersistentInkCoordinateSpace.self, from: JSONEncoder().encode(space))
    }
}

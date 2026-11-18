import CoreGraphics
import Foundation
import XCTest
@testable import iChart

#if canImport(UIKit)
import PDFKit
import UIKit
#endif

final class AnnotationPlacementRegressionTests: XCTestCase {
    private static let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testCrowdedAnnotationsKeepClearanceThroughRowsAndPagesInBothStyles() throws {
        for style in Self.styles {
            let fixture = try Self.crowdedChart(style: style, measureCount: 30)
            let persisted = fixture.chart
            let measureIDs = persisted.measures.map(\.id)
            let original = layout(persisted)
            XCTAssertGreaterThan(original.pages.count, 1)
            try assertCrowdedAnnotations(fixture, in: original)

            var reflowed = persisted
            XCTAssertTrue(reflowed.insertSystemBreak(before: measureIDs[1]))
            let afterReflow = layout(reflowed, width: 640)
            XCTAssertEqual(reflowed.measures.map(\.id), measureIDs)
            XCTAssertEqual(reflowed.cueTexts, persisted.cueTexts)
            for originalObject in persisted.roadmapObjects {
                let object = try XCTUnwrap(reflowed.roadmapObject(id: originalObject.id))
                XCTAssertEqual(object.startMeasureID, originalObject.startMeasureID)
                XCTAssertEqual(object.endMeasureID, originalObject.endMeasureID)
            }
            let firstRow = try XCTUnwrap(afterReflow.systems.first)
            XCTAssertFalse(firstRow.measures.contains { $0.sourceMeasureID == measureIDs[1] })
            try assertCrowdedAnnotations(fixture, in: afterReflow)
            XCTAssertEqual(fixture.chart, persisted)
        }
    }

    func testManualMovesSurviveReopeningAndResetToDefaultWithoutMovingAnchors() throws {
        for style in Self.styles {
            var chart = Chart.blank(title: "Movable annotations", measureCount: 4, layoutStyle: style)
            let ids = chart.measures.map(\.id)
            let cueID = try XCTUnwrap(chart.addCueText("Softer here", anchorMeasureID: ids[0], position: .below))
            XCTAssertTrue(chart.moveCueText(cueID, to: ids[0], atFraction: 0.25))
            let markerID = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: ids[1]))
            let endingID = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[2], endMeasureID: ids[3],
                displayText: "First time", endStyle: .open))
            let endingIndex = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == endingID })
            let sourceInk = Data([0x01, 0x02, 0x03])
            chart.roadmapObjects[endingIndex].sourceInkData = sourceInk
            let before = try annotationOffsets(in: layout(chart), ids: (cueID, markerID, endingID), anchors: ids)

            XCTAssertTrue(chart.setCueTextVerticalOffset(cueID, to: 28))
            XCTAssertTrue(chart.setRoadmapAnnotationVerticalOffset(markerID, to: -28))
            XCTAssertTrue(chart.setRoadmapAnnotationVerticalOffset(endingID, to: -28))
            let data = try ChartPersistenceCoders.encoder.encode(chart)
            var reopened = try ChartPersistenceCoders.decoder.decode(Chart.self, from: data)
            XCTAssertEqual(reopened.measures.map(\.id), ids)
            let cue = try XCTUnwrap(reopened.cueTexts.first { $0.id == cueID })
            XCTAssertEqual(cue.anchorMeasureID, ids[0])
            XCTAssertEqual(cue.beatFraction, 0.25)
            XCTAssertEqual(cue.position, .below)
            XCTAssertEqual(cue.verticalOffset, 28)
            let marker = try XCTUnwrap(reopened.roadmapObject(id: markerID))
            XCTAssertEqual(marker.startMeasureID, ids[1])
            XCTAssertEqual(marker.verticalOffset, -28)
            let ending = try XCTUnwrap(reopened.roadmapObject(id: endingID))
            XCTAssertEqual(ending.startMeasureID, ids[2])
            XCTAssertEqual(ending.endMeasureID, ids[3])
            XCTAssertEqual(ending.endingEndStyle, .open)
            XCTAssertEqual(ending.displayText, "First time")
            XCTAssertEqual(ending.sourceInkData, sourceInk)
            XCTAssertEqual(ending.verticalOffset, -28)

            let after = try annotationOffsets(in: layout(reopened), ids: (cueID, markerID, endingID), anchors: ids)
            XCTAssertGreaterThan(after.cue, before.cue + 1)
            XCTAssertLessThan(after.marker, before.marker - 1)
            XCTAssertLessThan(after.ending, before.ending - 1)

            XCTAssertTrue(reopened.setCueTextVerticalOffset(cueID, to: 0))
            XCTAssertTrue(reopened.setRoadmapAnnotationVerticalOffset(markerID, to: 0))
            XCTAssertTrue(reopened.setRoadmapAnnotationVerticalOffset(endingID, to: 0))
            XCTAssertNil(reopened.roadmapObject(id: markerID)?.verticalOffset)
            XCTAssertNil(reopened.roadmapObject(id: endingID)?.verticalOffset)
            let reset = try annotationOffsets(in: layout(reopened), ids: (cueID, markerID, endingID), anchors: ids)
            XCTAssertEqual(reset.cue, before.cue, accuracy: 0.001)
            XCTAssertEqual(reset.marker, before.marker, accuracy: 0.001)
            XCTAssertEqual(reset.ending, before.ending, accuracy: 0.001)
        }
    }

    private func annotationOffsets(in layout: LeadSheetPageLayout,
        ids: (cue: UUID, marker: UUID, ending: UUID), anchors: [UUID]
    ) throws -> (cue: CGFloat, marker: CGFloat, ending: CGFloat) {
        let measures = layout.systems.flatMap(\.measures)
        let cueMeasure = try XCTUnwrap(measures.first { $0.sourceMeasureID == anchors[0] })
        let markerMeasure = try XCTUnwrap(measures.first { $0.sourceMeasureID == anchors[1] })
        let endingMeasure = try XCTUnwrap(measures.first { $0.sourceMeasureID == anchors[2] })
        let cue = try XCTUnwrap(cueMeasure.cueTextLayouts.first { $0.id == ids.cue })
        let marker = try XCTUnwrap(layout.systems.flatMap(\.roadmapMarkerLayouts).first { $0.roadmapObjectID == ids.marker })
        let ending = try XCTUnwrap(layout.systems.flatMap(\.endingLayouts).first { $0.roadmapObjectID == ids.ending && $0.showsText })
        return (cue.frame.minY - cueMeasure.staffFrame.minY,
            marker.frame.minY - markerMeasure.staffFrame.minY,
            ending.frame.minY - endingMeasure.staffFrame.minY)
    }

    #if canImport(UIKit)
    @MainActor
    func testExportUsesResolvedAnnotationPositionsInBothStyles() async throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        for style in Self.styles {
            var fixture = try Self.crowdedChart(style: style)
            XCTAssertTrue(fixture.chart.setRoadmapAnnotationVerticalOffset(fixture.markerID, to: -20))
            let pageLayout = layout(fixture.chart, width: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth)
            try assertCrowdedAnnotations(fixture, in: pageLayout)
            let system = try XCTUnwrap(pageLayout.systems.first)
            let paper = try XCTUnwrap(pageLayout.pages.first { $0.systemIDs.contains(system.id) })
            let cue = try XCTUnwrap(system.measures.flatMap(\.cueTextLayouts).first { $0.id == fixture.cueID })
            let ending = try XCTUnwrap(system.endingLayouts.first { $0.roadmapObjectID == fixture.endingID })
            let marker = try XCTUnwrap(system.roadmapMarkerLayouts.first { $0.roadmapObjectID == fixture.markerID })
            let file = try await exporter.exportPDF(for: fixture.chart)
            let proof = XCTAttachment(data: try Data(contentsOf: file.url), uniformTypeIdentifier: "com.adobe.pdf")
            proof.name = "Annotation-clearance-\(style.rawValue).pdf"
            proof.lifetime = .keepAlways
            add(proof)
            let pdf = try XCTUnwrap(PDFDocument(url: file.url))
            XCTAssertEqual(pdf.pageCount, pageLayout.pages.count)
            let page = try XCTUnwrap(pdf.page(at: paper.index))
            let text = try XCTUnwrap(page.string) as NSString
            for (label, rect) in [
                ("Muted attack", cue.frame),
                ("Build to chorus", cue.frame),
                ("First pass", ending.labelFrame),
                ("FINE AT CUE", LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker))
            ] {
                let range = text.range(of: label, options: .caseInsensitive)
                guard range.location != NSNotFound else {
                    XCTFail("\(style) PDF omitted \(label)")
                    continue
                }
                let selection = try XCTUnwrap(page.selection(for: range))
                let ink = selection.bounds(for: page)
                let expected = CGRect(x: rect.minX - paper.frame.minX, y: paper.frame.maxY - rect.maxY,
                    width: rect.width, height: rect.height)
                XCTAssertFalse(ink.isEmpty)
                XCTAssertTrue(expected.insetBy(dx: -2, dy: -2).contains(ink),
                    "\(style) PDF \(label) painted \(ink) outside resolved frame \(expected)")
            }
        }
    }
    #endif

    private func assertCrowdedAnnotations(_ fixture: Fixture, in layout: LeadSheetPageLayout,
        file: StaticString = #filePath, line: UInt = #line) throws {
        let occurrences = layout.systems.flatMap { system in
            system.endingLayouts.filter { $0.roadmapObjectID == fixture.continuingEndingID }
        }
        XCTAssertGreaterThan(occurrences.count, 1, file: file, line: line)
        XCTAssertEqual(occurrences.filter(\.showsText).count, 1, file: file, line: line)
        XCTAssertEqual(occurrences.filter(\.showsLeadingHook).count, 1, file: file, line: line)
        XCTAssertEqual(occurrences.filter(\.showsTrailingHook).count, 1, file: file, line: line)
        XCTAssertTrue(occurrences.last?.showsTrailingHook == true, file: file, line: line)

        for page in layout.pages {
            let systems = layout.systems.filter { page.systemIDs.contains($0.id) }
            for system in systems {
                let boxes = annotationBoxes(system)
                for (index, box) in boxes.enumerated() {
                    XCTAssertTrue(page.frame.insetBy(dx: -0.01, dy: -0.01).contains(box.frame),
                        "\(fixture.chart.layoutStyle) \(box.label) extends outside page \(page.index)", file: file, line: line)
                    for other in boxes.dropFirst(index + 1) {
                        let overlap = box.frame.intersection(other.frame)
                        XCTAssertTrue(overlap.isNull || overlap.width < 0.01 || overlap.height < 0.01,
                            "\(fixture.chart.layoutStyle) row \(system.index): \(box.label) and \(other.label) overlap by \(overlap)",
                            file: file, line: line)
                    }
                }
            }
            for (earlier, later) in zip(systems, systems.dropFirst()) {
                let earlierContent = earlier.spacingContentBounds(for: fixture.chart)
                let laterContent = later.spacingContentBounds(for: fixture.chart)
                XCTAssertLessThanOrEqual(earlierContent.maxY, laterContent.minY + 0.01,
                    "\(fixture.chart.layoutStyle) annotations must have room between adjacent rows", file: file, line: line)
            }
        }
    }

    private func annotationBoxes(_ system: LeadSheetSystemLayout) -> [(label: String, frame: CGRect)] {
        let cues = system.measures.flatMap(\.cueTextLayouts).map { ("cue \($0.text)", $0.frame) }
        let endings = system.endingLayouts.map { ("ending \($0.text)", $0.occupiedFrame) }
        let markers = system.roadmapMarkerLayouts.map {
            ("form \($0.text)", LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: $0))
        }
        return cues + endings + markers
    }

    private func layout(_ chart: Chart, width: CGFloat = 932) -> LeadSheetPageLayout {
        LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: width, height: 1_100))
    }

    private struct Fixture {
        var chart: Chart
        let cueID: UUID
        let endingID: UUID
        let markerID: UUID
        let continuingEndingID: UUID
    }

    private static func crowdedChart(style: ChartLayoutStyle, measureCount: Int = 6) throws -> Fixture {
        var chart = Chart.blank(title: "Overlapping chart annotations", measureCount: measureCount, layoutStyle: style)
        chart.engravingPreset = .balanced
        chart.staffSystemDensity = .dense
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: 3).enumerated().map { index, start in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced,
                measures: Array(measures[start..<min(start + 3, measures.count)]))
        }
        for id in measures.map(\.id) {
            chart.setMeasureManualLayoutWidth(144, for: id)
        }
        let anchor = measures[0].id
        let cue = try XCTUnwrap(chart.addCueText("Muted attack\nBuild to chorus", anchorMeasureID: anchor, position: .above))
        let ending = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: anchor, endMeasureID: anchor,
            displayText: "First pass only", endStyle: .open))
        let marker = try XCTUnwrap(chart.addPointRoadmapMarker(.fine, anchorMeasureID: anchor, displayText: "Fine at cue"))
        _ = try XCTUnwrap(chart.addPointRoadmapMarker(.dcAlFine, anchorMeasureID: anchor))
        _ = try XCTUnwrap(chart.addCueText("Wait for the count", anchorMeasureID: anchor, position: .below))
        let continuing = try XCTUnwrap(chart.addEndingSpan(.ending2, startMeasureID: anchor,
            endMeasureID: try XCTUnwrap(measures.last?.id), displayText: "Second pass", endStyle: .closed))
        for index in stride(from: 3, to: measures.count, by: 3) {
            _ = try XCTUnwrap(chart.addCueText("Listen for the downbeat", anchorMeasureID: measures[index].id, position: .above))
            _ = try XCTUnwrap(chart.addPointRoadmapMarker(.dc, anchorMeasureID: measures[index].id))
        }
        return Fixture(chart: chart, cueID: cue, endingID: ending, markerID: marker, continuingEndingID: continuing)
    }
}

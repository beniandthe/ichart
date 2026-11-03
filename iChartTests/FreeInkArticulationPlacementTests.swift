import CoreGraphics
import XCTest
@testable import iChart

#if canImport(UIKit)
import PDFKit
import UIKit
#endif

final class FreeInkArticulationPlacementTests: XCTestCase {
    func testMeasureAndBeatRemainAnchoredAfterReflowAndEngravingChange() throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.last?.id)
        let size = CGSize(width: 850, height: 1_100)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let initialTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 2, chart: chart, pageLayout: initialLayout
        ))
        XCTAssertEqual(FreeInkArticulationPlacement.target(
            near: initialTarget.center, chart: chart, pageLayout: initialLayout
        ), initialTarget)

        XCTAssertTrue(chart.insertSystemBreak(before: measureID))
        chart.engravingPreset = .compact
        let movedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let movedTarget = try XCTUnwrap(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 2, chart: chart, pageLayout: movedLayout
        ))
        let movedSystem = try XCTUnwrap(movedLayout.systems.first {
            $0.measures.contains(where: { $0.sourceMeasureID == measureID })
        })
        let movedMeasure = try XCTUnwrap(movedSystem.measures.first { $0.sourceMeasureID == measureID })
        XCTAssertGreaterThan(movedTarget.center.y, initialTarget.center.y)
        XCTAssertEqual(movedTarget.center.x, movedMeasure.staffFrame.minX + 8
            + (movedMeasure.staffFrame.width - 16) * 2.5 / 4, accuracy: 0.01)
        XCTAssertEqual(movedTarget.center.y, try XCTUnwrap(movedSystem.staffLineYPositions.first)
            - movedTarget.staffSpace * 0.6, accuracy: 0.01)
        XCTAssertEqual(FreeInkArticulationPlacement.target(
            near: movedTarget.center, chart: chart, pageLayout: movedLayout
        ), movedTarget)
    }

    func testPlacementRequiresRealRhythmMeasureAndInRangeBeat() throws {
        let size = CGSize(width: 850, height: 1_100)
        let chart = makeChart()
        let rhythmLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertNil(FreeInkArticulationPlacement.target(
            measureID: measureID, beatIndex: 4, chart: chart, pageLayout: rhythmLayout
        ))
        XCTAssertNil(FreeInkArticulationPlacement.target(
            near: rhythmLayout.header.handwrittenFrame.origin, chart: chart, pageLayout: rhythmLayout
        ))
        let simpleChart = makeChart(style: .simpleChordSheet)
        let simpleLayout = LeadSheetPageLayoutEngine.pageLayout(for: simpleChart, pageSize: size)
        XCTAssertNil(FreeInkArticulationPlacement.target(
            measureID: try XCTUnwrap(simpleChart.measures.first?.id), beatIndex: 0,
            chart: simpleChart, pageLayout: simpleLayout
        ))
    }

    func testPlacementAcceptsMarkJustAboveOneSystemAndWithinItsMeasure() throws {
        let chart = makeChart()
        var layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 850, height: 1_100))
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first)
        let staffSpace = system.staffLineYPositions[1] - system.staffLineYPositions[0]
        let mark = CGPoint(x: measure.staffFrame.midX, y: system.frame.minY - 0.82 * staffSpace)
        XCTAssertEqual(FreeInkArticulationPlacement.target(near: mark, chart: chart, pageLayout: layout)?.measureID,
            measure.sourceMeasureID)
        XCTAssertNil(FreeInkArticulationPlacement.target(
            near: CGPoint(x: mark.x, y: system.frame.minY - 1.1 * staffSpace), chart: chart, pageLayout: layout
        ))
        XCTAssertNil(FreeInkArticulationPlacement.target(
            near: CGPoint(x: measure.staffFrame.minX - 1, y: mark.y), chart: chart, pageLayout: layout
        ))

        // A point with two possible systems must remain ordinary ink.
        layout.systems.append(system)
        XCTAssertNil(FreeInkArticulationPlacement.target(near: mark, chart: chart, pageLayout: layout))
    }

    func testFloatingMarkKeepsItsPaperPointAcrossPageOffsets() throws {
        let chart = makeChart()
        var layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 850, height: 1_100))
        let page = try XCTUnwrap(layout.pages.first)
        let blankPoint = CGPoint(x: page.frame.midX, y: page.frame.maxY - 120)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: blankPoint, chart: chart, pageLayout: layout))
        let position = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at: blankPoint, pageLayout: layout))
        let mark = FreeInkArticulation(kind: .fermata, sourceInkData: Data(), pagePoint: position)
        let target = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout))
        XCTAssertNil(target.measureID)
        XCTAssertEqual(target.center, blankPoint)

        layout.pages[0].frame = page.frame.offsetBy(dx: 24, dy: 36)
        XCTAssertEqual(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout)?.center,
            CGPoint(x: blankPoint.x + 24, y: blankPoint.y + 36))

        let secondPagePoint = FreeInkArticulationPagePoint(pageIndex: 1,
            x: position.x, y: page.frame.height + 30)
        let lastPage = layout.pages[0].frame
        let recoveredCenter = try XCTUnwrap(FreeInkArticulationPlacement.center(for: secondPagePoint, pageLayout: layout))
        XCTAssertEqual(recoveredCenter.x, lastPage.minX + position.x, accuracy: 0.01)
        XCTAssertEqual(recoveredCenter.y, lastPage.maxY - 10, accuracy: 0.01)
    }

    func testAttachmentDistinguishesRenderedChordAndNoteFromEmptySpace() throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.last?.id)
        XCTAssertTrue(chart.appendRecognizedChord(
            ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
            rawInput: "C", to: measureID, atFraction: 0
        ))
        chart.systems[0].measures[1].rhythmMap = MeasureRhythmMap(values: [.quarter, .quarter, .quarter, .quarter])
        let size = CGSize(width: 850, height: 1_100)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        let chord = try XCTUnwrap(measure.chordLayouts.first)
        let chordHit = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: CGPoint(x: chord.frame.midX, y: chord.frame.midY), chart: chart, pageLayout: layout
        ))
        XCTAssertEqual(chordHit.measureID, measureID)
        XCTAssertEqual(chordHit.attachment, .chord(id: chord.id))
        XCTAssertEqual(chordHit.guidePoint, CGPoint(x: chord.frame.midX, y: chord.frame.minY))

        let note = try XCTUnwrap(measure.noteLayouts.dropFirst().first)
        let noteHit = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: CGPoint(x: note.noteheadFrame.midX, y: note.noteheadFrame.midY), chart: chart, pageLayout: layout
        ))
        XCTAssertEqual(noteHit.measureID, measureID)
        XCTAssertEqual(noteHit.attachment, .note(beat: 2, subdivision: 0))
        XCTAssertEqual(noteHit.guidePoint, CGPoint(x: note.noteheadFrame.midX, y: note.noteheadFrame.minY))
        let mark = FreeInkArticulation(kind: .accent, measureID: measureID, sourceInkData: Data(),
            attachment: noteHit.attachment)
        let secondMark = FreeInkArticulation(kind: .fermata, measureID: measureID, sourceInkData: Data(),
            attachment: noteHit.attachment)
        chart.freeInkArticulations = [mark, secondMark]
        let original = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: layout))
        let stacked = try XCTUnwrap(FreeInkArticulationPlacement.target(for: secondMark, chart: chart, pageLayout: layout))
        XCTAssertEqual(stacked.center.x, original.center.x)
        XCTAssertLessThan(stacked.markFrame.maxY, original.markFrame.minY)

        XCTAssertTrue(chart.insertSystemBreak(before: measureID))
        let reflowed = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        let moved = try XCTUnwrap(FreeInkArticulationPlacement.target(for: mark, chart: chart, pageLayout: reflowed))
        let movedMeasure = try XCTUnwrap(reflowed.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID })
        XCTAssertEqual(moved.center.x, movedMeasure.noteLayouts[1].noteheadFrame.midX, accuracy: 0.01)
        XCTAssertGreaterThan(moved.center.y, original.center.y)

        let chordMark = FreeInkArticulation(kind: .fermata, measureID: measureID, sourceInkData: Data(),
            attachment: chordHit.attachment)
        let destination = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.moveChordEvent(chord.id, to: destination, atFraction: 0.4))
        let movedChordLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size)
        XCTAssertEqual(FreeInkArticulationPlacement.target(for: chordMark, chart: chart, pageLayout: movedChordLayout)?.measureID,
            destination)
    }

    func testGuideRetainsItsChordUntilLeavingTheChordHitRange() throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertTrue(chart.appendRecognizedChord(
            ChordSymbol(root: .c, accidental: .natural, quality: "", extensions: [], alterations: [], slashBass: nil),
            rawInput: "C", to: measureID, atFraction: 0.25
        ))
        var layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 850, height: 1_100))
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.first)
        let first = try XCTUnwrap(measure.chordLayouts.first)
        let space = system.staffLineYPositions[1] - system.staffLineYPositions[0]
        var second = first
        second.id = UUID()
        second.frame = first.frame.offsetBy(dx: first.frame.width + 0.2 * space, dy: 0)
        layout.systems[0].measures[0].chordLayouts.append(second)

        let acquired = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: CGPoint(x: first.frame.midX, y: first.frame.midY), chart: chart, pageLayout: layout
        ))
        XCTAssertEqual(acquired.attachment, .chord(id: first.id))
        let overlap = CGPoint(x: first.frame.maxX + 0.65 * space, y: first.frame.midY)
        XCTAssertTrue(acquired.retains(at: overlap))
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(
            near: overlap, chart: chart, pageLayout: layout
        )?.attachment, .chord(id: second.id))
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(
            near: overlap, chart: chart, pageLayout: layout, retaining: acquired
        ), acquired)

        let beyondFirst = CGPoint(x: first.frame.maxX + 1.1 * space, y: first.frame.midY)
        XCTAssertFalse(acquired.retains(at: beyondFirst))
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(
            near: beyondFirst, chart: chart, pageLayout: layout, retaining: acquired
        )?.attachment, .chord(id: second.id))
        let beyondBoth = CGPoint(x: second.frame.maxX + 2 * space, y: first.frame.minY - 2 * space)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(
            near: beyondBoth, chart: chart, pageLayout: layout, retaining: acquired
        ))
    }

    func testInkNearAStaffCanAttachWithoutRenderedNotes() throws {
        let chart = makeChart()
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 850, height: 1_100))
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let staff = measure.staffFrame
        let point = CGPoint(x: staff.midX, y: staff.minY - 4)
        XCTAssertNil(FreeInkArticulationPlacement.attachment(near: point, chart: chart, pageLayout: layout))
        let stroke = CGRect(x: staff.midX - 3, y: staff.minY + 1, width: 6, height: 8)
        let hit = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: point, chart: chart, pageLayout: layout, staffInkBounds: [stroke]
        ))
        XCTAssertEqual(hit.measureID, measure.sourceMeasureID)
        guard case .staff(let x, let y) = hit.attachment else { return XCTFail("Expected a staff attachment") }
        XCTAssertEqual(x, 0.5, accuracy: 0.01)
        XCTAssertLessThan(y, 0)
        XCTAssertEqual(hit.guidePoint, CGPoint(x: stroke.midX, y: stroke.minY))
        let secondStroke = stroke.offsetBy(dx: 9, dy: 0)
        let secondPoint = CGPoint(x: secondStroke.midX, y: point.y)
        XCTAssertTrue(hit.retains(at: secondPoint))
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(
            near: secondPoint, chart: chart, pageLayout: layout, staffInkBounds: [stroke, secondStroke]
        )?.guidePoint, CGPoint(x: secondStroke.midX, y: secondStroke.minY))
        XCTAssertEqual(FreeInkArticulationPlacement.attachment(
            near: secondPoint, chart: chart, pageLayout: layout,
            staffInkBounds: [stroke, secondStroke], retaining: hit
        ), hit)
        let away = CGPoint(x: staff.midX, y: staff.minY - 30)
        XCTAssertFalse(hit.retains(at: away))
        XCTAssertNil(FreeInkArticulationPlacement.attachment(
            near: away, chart: chart, pageLayout: layout,
            staffInkBounds: [stroke, secondStroke], retaining: hit
        ))
        let staffCenter = CGPoint(x: staff.midX, y: staff.midY)
        let bareStaff = try XCTUnwrap(FreeInkArticulationPlacement.attachment(
            near: staffCenter, chart: chart, pageLayout: layout
        ))
        XCTAssertFalse(bareStaff.retains(at: staffCenter))
    }

    func testLastConversionRetainsSavedPaperWidthAndRemainingInkTakesPrecedence() throws {
        var chart = makeChart()
        let archivedSpace = PersistentInkCoordinateSpace(width: 560, height: 1_100)
        let visibleSpace = PersistentInkCoordinateSpace(width: 920, height: 1_100)
        chart.pageHandwrittenNotationData = Data([0x01])
        chart.pageHandwrittenNotationCoordinateSpace = archivedSpace
        let originalWidth = try XCTUnwrap(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart))
        let originalSize = CGSize(width: originalWidth, height: 1_100)
        let originalPaper = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: originalSize).paperFrame
        chart.freeInkArticulations = [FreeInkArticulation(kind: .fermata,
            measureID: try XCTUnwrap(chart.measures.first?.id), beatIndex: 0,
            sourceInkData: Data([0x01]), sourceCoordinateSpace: archivedSpace)]

        chart.pageHandwrittenNotationCoordinateSpace = visibleSpace
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.savedPageCoordinateSpace(for: chart), visibleSpace)

        chart.pageHandwrittenNotationData = nil
        chart.pageHandwrittenNotationCoordinateSpace = nil
        XCTAssertEqual(LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart), originalWidth)
        XCTAssertEqual(LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: originalSize).paperFrame, originalPaper)
    }

    private func makeChart(style: ChartLayoutStyle = .rhythmSectionSheet) -> Chart {
        var chart = Chart.draft(title: "Articulation placement", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 2)
        chart.stylePreset = .plainWhite
        return chart
    }

    #if canImport(UIKit)
    @MainActor
    func testExportDrawsAttachedAndFloatingArticulations() async throws {
        var chart = makeChart()
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth, height: 1_100))
        var targets = try [1, 2].map { beat in
            try XCTUnwrap(FreeInkArticulationPlacement.target(
                measureID: measureID, beatIndex: beat, chart: chart, pageLayout: layout
            ))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = PDFChartExporter(exportDirectory: directory)
        let baseline = try await renderedPage(for: chart, exporter: exporter)
        chart.freeInkArticulations = zip([FreeInkArticulationKind.fermata, .accent], targets).map { kind, target in
            FreeInkArticulation(kind: kind, measureID: measureID, beatIndex: target.beatIndex,
                                sourceInkData: Data([0x01]), sourceCoordinateSpace: nil)
        }
        let floatingPoint = CGPoint(x: layout.paperFrame.midX, y: layout.paperFrame.maxY - 120)
        let pagePoint = try XCTUnwrap(FreeInkArticulationPlacement.pagePoint(at: floatingPoint, pageLayout: layout))
        let floating = FreeInkArticulation(kind: .accent, sourceInkData: Data([0x01]), pagePoint: pagePoint)
        chart.freeInkArticulations.append(floating)
        targets.append(try XCTUnwrap(FreeInkArticulationPlacement.target(for: floating, chart: chart, pageLayout: layout)))
        let withMarks = try await renderedPage(for: chart, exporter: exporter)
        let paper = layout.paperFrame
        for target in targets {
            let roi = target.markFrame.offsetBy(dx: -paper.minX, dy: -paper.minY)
            XCTAssertGreaterThan(try darkPixels(in: withMarks, rect: roi) - darkPixels(in: baseline, rect: roi), 4)
        }
    }

    @MainActor
    private func renderedPage(for chart: Chart, exporter: PDFChartExporter) async throws -> CGImage {
        let exported = try await exporter.exportPDF(for: chart)
        let document = try XCTUnwrap(PDFDocument(url: exported.url))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(bounds)
            renderer.cgContext.translateBy(x: 0, y: bounds.height)
            renderer.cgContext.scaleBy(x: 1, y: -1)
            page.draw(with: .mediaBox, to: renderer.cgContext)
        }
        return try XCTUnwrap(image.cgImage)
    }

    private func darkPixels(in image: CGImage, rect: CGRect) throws -> Int {
        let crop = try XCTUnwrap(image.cropping(to: rect.integral))
        let bytesPerRow = crop.width * 4
        var pixels = [UInt8](repeating: 255, count: bytesPerRow * crop.height)
        let drawn = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
            return true
        }
        XCTAssertTrue(drawn)
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 100 && pixels[$0 + 1] < 100 && pixels[$0 + 2] < 100
        }.count
    }
    #endif
}

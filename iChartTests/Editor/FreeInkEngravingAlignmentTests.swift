#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Engraving changes musical geometry; rotation only changes the viewport.
/// Assertions use the actual five staff lines, independently of the ink policy.
@MainActor
final class FreeInkEngravingAlignmentTests: XCTestCase {
    private let pageSize = CGSize(width: 1_200, height: 1_200)

    func testEveryEngravingTransitionPreservesHandwrittenStaffPositionsAcrossStaffLayouts() throws {
        for style in [ChartLayoutStyle.leadSheet, .rhythmSectionSheet] {
            for before in EngravingPreset.allCases {
                for after in EngravingPreset.allCases where before != after {
                    var chart = makeChart(style, preset: before)
                    let source = try geometry(chart)
                    XCTAssertGreaterThanOrEqual(source.layout.systems.count, 2)
                    let ink = staffNotation(in: source)
                    let sourceBytes = ink.dataRepresentation()
                    chart.setEngravingPreset(after)
                    let target = try geometry(chart)
                    let projected = project(ink, from: source.space, to: target.space)

                    assertStaffPositions(of: ink, in: source, match: projected, in: target,
                        context: "\(style.rawValue): \(before.rawValue) -> \(after.rawValue)")
                    XCTAssertEqual(ink.dataRepresentation(), sourceBytes,
                        "Display projection must preserve the original drawing archive.")
                    XCTAssertEqual(projected.strokes.map(\.randomSeed), ink.strokes.map(\.randomSeed))
                }
            }
        }
    }

    func testMixedManualAndDefaultWidthsPreserveEachNotesMeasureAndPitchAcrossAllPresetPairs() throws {
        for before in EngravingPreset.allCases {
            for after in EngravingPreset.allCases where before != after {
                var chart = makeChart(.leadSheet, preset: before)
                // Manual widths remain fixed while neighboring default widths
                // follow engraving metrics. One affine transform for the whole
                // row therefore cannot preserve its internal measure boundaries.
                chart.systems[0].measures[0].manualLayoutWidth = 140
                chart.systems[0].measures[2].manualLayoutWidth = 180
                chart.systems[1].measures[1].manualLayoutWidth = 115
                chart.systems[1].measures[3].manualLayoutWidth = 170
                let source = try geometry(chart)
                var strokes: [PKStroke] = []
                var notes: [(measureID: UUID, range: Range<Int>, staff: CGRect)] = []
                for system in source.staffSystems {
                    let measures = system.measures.filter { $0.sourceMeasureID != nil }
                    XCTAssertEqual(measures.count, 4,
                        "Mixed widths must retain the fixture's explicit four-measure rows.")
                    for boundary in 0..<max(0, measures.count - 1) {
                        // Keep the notes on either side spatially separate.
                        // Each four-stroke note is connected within its own bar.
                        for (measure, isLeft) in [(measures[boundary], true), (measures[boundary + 1], false)] {
                            let measureID = try XCTUnwrap(measure.sourceMeasureID)
                            let staff = measure.staffFrame.insetBy(dx: 0, dy: 2)
                                .offsetBy(dx: -source.frame.minX, dy: -source.frame.minY)
                            let spacing = staff.height / 4
                            let x = isLeft ? staff.maxX - 24 : staff.minX + 20
                            let y = staff.minY + (isLeft ? 1.5 : 3) * spacing
                            let seed = UInt32(20_000 + notes.count * 10)
                            let firstStroke = strokes.count
                            strokes.append(stroke([CGPoint(x: x, y: y), CGPoint(x: x + 6, y: y - 2),
                                CGPoint(x: x + 8, y: y), CGPoint(x: x + 2, y: y + 2), CGPoint(x: x, y: y)], seed: seed + 1))
                            strokes.append(stroke([CGPoint(x: x + 8, y: y),
                                CGPoint(x: x + 8, y: y - 2.5 * spacing)], seed: seed + 2))
                            strokes.append(stroke([CGPoint(x: x - 9, y: y - 6),
                                CGPoint(x: x - 9, y: y + 5), CGPoint(x: x - 4, y: y)], seed: seed + 3))
                            strokes.append(stroke([CGPoint(x: x + 8, y: y - 2.5 * spacing),
                                CGPoint(x: x + 17, y: y - 2.3 * spacing)], seed: seed + 4))
                            notes.append((measureID, firstStroke..<strokes.count, staff))
                        }
                    }
                }
                let original = PKDrawing(strokes: strokes)
                let sourceBytes = original.dataRepresentation()
                let sourceSpace = source.space
                chart.pageHandwrittenNotationData = sourceBytes
                chart.pageHandwrittenNotationCoordinateSpace = sourceSpace
                chart.setEngravingPreset(after)
                let target = try geometry(chart)
                let context = "\(before.rawValue) -> \(after.rawValue)"
                let sourceRows = source.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
                let targetRows = target.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
                XCTAssertEqual(sourceRows, targetRows,
                    "This case must exercise internal bar widths, independently of row reflow: \(context)")
                let targetMeasures = Dictionary(target.staffSystems.flatMap(\.measures).compactMap { measure in
                    measure.sourceMeasureID.map { ($0, measure) }
                }, uniquingKeysWith: { first, _ in first })

                // Independently demonstrate why the previous whole-row policy
                // is insufficient, using actual rendered barline coordinates.
                var largestWholeRowBoundaryDrift: CGFloat = 0
                for (sourceSystem, targetSystem) in zip(source.staffSystems, target.staffSystems) {
                    let sourceMeasures = sourceSystem.measures.filter { $0.sourceMeasureID != nil }
                    let targetRowMeasures = targetSystem.measures.filter { $0.sourceMeasureID != nil }
                    let sourceSpan = sourceMeasures.reduce(CGRect.null) { $0.union($1.staffFrame) }
                    let targetSpan = targetRowMeasures.reduce(CGRect.null) { $0.union($1.staffFrame) }
                    let rowScale = targetSpan.width / sourceSpan.width
                    for measure in sourceMeasures.dropLast() {
                        let destination = try XCTUnwrap(targetMeasures[try XCTUnwrap(measure.sourceMeasureID)])
                        let mappedBoundary = targetSpan.minX + (measure.staffFrame.maxX - sourceSpan.minX) * rowScale
                        largestWholeRowBoundaryDrift = max(largestWholeRowBoundaryDrift,
                            abs(mappedBoundary - destination.staffFrame.maxX))
                    }
                }
                XCTAssertGreaterThan(largestWholeRowBoundaryDrift, 0.1,
                    "Fixture must expose a measurable internal-boundary error under one row transform: \(context)")

                let projected = project(original, from: sourceSpace, to: target.space)
                XCTAssertEqual(projected.strokes.count, original.strokes.count, context)
                guard projected.strokes.count == original.strokes.count else { continue }
                for note in notes {
                    let destination = try XCTUnwrap(targetMeasures[note.measureID])
                    let targetStaff = destination.staffFrame.insetBy(dx: 0, dy: 2)
                        .offsetBy(dx: -target.frame.minX, dy: -target.frame.minY)
                    let commonTransform = projected.strokes[note.range.lowerBound].transform
                    for index in note.range {
                        let oldStroke = original.strokes[index]
                        let newStroke = projected.strokes[index]
                        assertTransform(newStroke.transform, equals: commonTransform,
                            context: "Connected note components must stay coherent: \(context)")
                        XCTAssertEqual(newStroke.randomSeed, oldStroke.randomSeed)
                        XCTAssertEqual(newStroke.path.count, oldStroke.path.count)
                        for (sourcePoint, targetPoint) in zip(oldStroke.path, newStroke.path) {
                            let old = sourcePoint.location.applying(oldStroke.transform)
                            let new = targetPoint.location.applying(newStroke.transform)
                            XCTAssertEqual((new.x - targetStaff.minX) / targetStaff.width,
                                (old.x - note.staff.minX) / note.staff.width, accuracy: 0.002,
                                "The note moved within or across its owning bar: \(context), stroke \(oldStroke.randomSeed)")
                            XCTAssertEqual((new.y - targetStaff.minY) / (targetStaff.height / 4),
                                (old.y - note.staff.minY) / (note.staff.height / 4), accuracy: 0.002,
                                "The note changed staff position: \(context), stroke \(oldStroke.randomSeed)")
                        }
                    }
                }
                XCTAssertEqual(original.dataRepresentation(), sourceBytes)
                XCTAssertEqual(chart.pageHandwrittenNotationData, sourceBytes)
                XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, sourceSpace)
            }
        }
    }

    func testEngravingReflowKeepsEachConnectedNoteWithItsMeasureAndDoesNotTearTopBoundaryBeam() throws {
        let narrowPage = CGSize(width: 800, height: 1_200)
        var chart = makeChart(.rhythmSectionSheet, preset: .wide, usesOpenMeasures: true)
        let source = try geometry(chart, pageSize: narrowPage)
        var strokes: [PKStroke] = []
        var notes: [(measureID: UUID, range: Range<Int>, staff: CGRect)] = []
        var boundaryBeamIndex: Int?
        var boundaryRowTop: CGFloat?
        for system in source.staffSystems {
            for measure in system.measures {
                guard let measureID = measure.sourceMeasureID else { continue }
                let staff = measure.staffFrame.insetBy(dx: 0, dy: 2)
                    .offsetBy(dx: -source.frame.minX, dy: -source.frame.minY)
                let spacing = staff.height / 4
                let x = staff.midX - 4
                let y = staff.minY + 1.5 * spacing
                let rowTop = system.frame.minY - source.frame.minY
                let isBoundaryNote = notes.isEmpty
                let stemTop = isBoundaryNote ? rowTop - 12 : y - 2.5 * spacing
                let seed = UInt32(1_000 + notes.count * 10)
                let firstStroke = strokes.count
                strokes.append(stroke([CGPoint(x: x, y: y), CGPoint(x: x + 6, y: y - 2),
                    CGPoint(x: x + 8, y: y), CGPoint(x: x + 2, y: y + 2), CGPoint(x: x, y: y)], seed: seed + 1))
                strokes.append(stroke([CGPoint(x: x + 8, y: y),
                    CGPoint(x: x + 8, y: stemTop)], seed: seed + 2))
                strokes.append(stroke([CGPoint(x: x - 9, y: y - 6),
                    CGPoint(x: x - 9, y: y + 5), CGPoint(x: x - 4, y: y)], seed: seed + 3))
                strokes.append(stroke([CGPoint(x: x + 8, y: stemTop),
                    CGPoint(x: x + 17, y: stemTop + 2)], seed: seed + 4))
                if isBoundaryNote {
                    boundaryBeamIndex = strokes.count - 1
                    boundaryRowTop = rowTop
                }
                notes.append((measureID, firstStroke..<strokes.count, staff))
            }
        }
        let original = PKDrawing(strokes: strokes)
        let originalBytes = original.dataRepresentation()
        let sourceSpace = source.space
        chart.pageHandwrittenNotationData = originalBytes
        chart.pageHandwrittenNotationCoordinateSpace = sourceSpace
        chart.setEngravingPreset(.compact)
        let target = try geometry(chart, pageSize: narrowPage)
        let sourceRows = source.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
        let targetRows = target.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
        XCTAssertNotEqual(sourceRows, targetRows,
            "The narrow-page fixture must exercise an actual change in measure-to-row membership.")
        let beamIndex = try XCTUnwrap(boundaryBeamIndex)
        XCTAssertLessThan(original.strokes[beamIndex].renderBounds.maxY, try XCTUnwrap(boundaryRowTop),
            "The separate beam must start above the row boundary, while its connected notehead lies on the staff.")
        let targetMeasures = Dictionary(target.staffSystems.flatMap(\.measures).compactMap { measure in
            measure.sourceMeasureID.map { ($0, measure) }
        }, uniquingKeysWith: { first, _ in first })
        let projected = project(original, from: sourceSpace, to: target.space)
        XCTAssertEqual(projected.strokes.count, original.strokes.count)
        guard projected.strokes.count == original.strokes.count else { return }
        for note in notes {
            let measure = try XCTUnwrap(targetMeasures[note.measureID])
            let targetStaff = measure.staffFrame.insetBy(dx: 0, dy: 2)
                .offsetBy(dx: -target.frame.minX, dy: -target.frame.minY)
            let commonTransform = projected.strokes[note.range.lowerBound].transform
            for index in note.range {
                let before = original.strokes[index]
                let after = projected.strokes[index]
                assertTransform(after.transform, equals: commonTransform,
                    context: "Connected notehead, stem, accidental and beam must use one transform after row reflow.")
                XCTAssertEqual(before.randomSeed, after.randomSeed)
                XCTAssertEqual(before.path.count, after.path.count)
                for (sourcePoint, targetPoint) in zip(before.path, after.path) {
                    let old = sourcePoint.location.applying(before.transform)
                    let new = targetPoint.location.applying(after.transform)
                    XCTAssertEqual((new.y - targetStaff.minY) / (targetStaff.height / 4),
                        (old.y - note.staff.minY) / (note.staff.height / 4), accuracy: 0.002,
                        "A connected note moved to another pitch or row after reflow.")
                    XCTAssertEqual((new.x - targetStaff.minX) / targetStaff.width,
                        (old.x - note.staff.minX) / note.staff.width, accuracy: 0.002,
                        "A connected note lost its horizontal position in its owning measure.")
                }
            }
        }
        XCTAssertEqual(original.dataRepresentation(), originalBytes)
        XCTAssertEqual(chart.pageHandwrittenNotationData, originalBytes)
        XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, sourceSpace)
    }

    func testCanonicalStyleCyclesDoNotAccumulatePitchOrStrokeGeometryChanges() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let original = staffNotation(in: source)
        let bytes = original.dataRepresentation()
        for _ in 0..<4 {
            for preset in [EngravingPreset.compact, .bold, .balanced, .wide] {
                chart.setEngravingPreset(preset)
                let target = try geometry(chart)
                let visible = project(original, from: source.space, to: target.space)
                assertStaffPositions(of: original, in: source, match: visible, in: target)
                if preset == .wide { assertSamePoints(original, visible) }
            }
        }
        XCTAssertEqual(original.dataRepresentation(), bytes)
    }

    func testViewportResizeAtSameEngravingKeepsAbsolutePaperCoordinates() throws {
        let chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let ink = staffNotation(in: source)
        let otherLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 800, height: 1_400))
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: otherLayout)
        let otherSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: otherLayout, relativeTo: frame))
        XCTAssertNotEqual(source.space.width, otherSpace.width,
            "This fixture must also guard the historical wider-paper rotation path.")
        assertSamePoints(ink, project(ink, from: source.space, to: otherSpace))
    }

    func testHeaderWritingRemainsFixedWhileStaffWritingFollowsEngraving() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let header = PKDrawing(strokes: [stroke([
            CGPoint(x: 40, y: 16), CGPoint(x: 60, y: 30), CGPoint(x: 80, y: 16)
        ], seed: 999)])
        let staff = staffNotation(in: source)
        let drawing = PKDrawing(strokes: header.strokes + staff.strokes)
        chart.setEngravingPreset(.compact)
        let target = try geometry(chart)
        let projected = project(drawing, from: source.space, to: target.space)
        assertSamePoints(header, PKDrawing(strokes: Array(projected.strokes.prefix(1))))
        assertStaffPositions(of: staff, in: source,
            match: PKDrawing(strokes: Array(projected.strokes.dropFirst())), in: target)
    }

    func testLegacyMeasureAnchorsRecoverOriginalStaffGeometryAfterStyleWasAlreadyChanged() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let ink = staffNotation(in: source)
        var legacy = source.space
        legacy.engravingPreset = nil
        legacy.measureAnchors = legacy.measureAnchors?.map { anchor in
            var anchor = anchor
            anchor.staffFrame = nil
            return anchor
        }
        let bytes = ink.dataRepresentation()
        chart.pageHandwrittenNotationData = bytes
        chart.pageHandwrittenNotationCoordinateSpace = legacy
        // Reproduce a chart saved by the old app after the reported bad change.
        chart.engravingPreset = .compact
        let target = try geometry(chart)
        let recovered = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
            legacy, chart: chart))
        XCTAssertEqual(recovered.engravingPreset, .wide)
        XCTAssertNotNil(recovered.measureAnchors?.first?.staffFrame)
        let projected = project(ink, from: recovered, to: target.space)
        assertStaffPositions(of: ink, in: source, match: projected, in: target)
        XCTAssertEqual(chart.pageHandwrittenNotationData, bytes)
        XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, legacy,
            "Legacy recovery for display must not rewrite persisted source metadata.")
    }

    func testUnmatchedLegacyLayoutPreservesInkRatherThanGuessingItsOriginalStaff() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let ink = staffNotation(in: source)
        var legacy = source.space
        legacy.engravingPreset = nil
        legacy.measureAnchors = legacy.measureAnchors?.map { anchor in
            var anchor = anchor
            anchor.staffFrame = nil
            anchor.frame.y += 17
            return anchor
        }
        chart.pageHandwrittenNotationData = ink.dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = legacy
        chart.engravingPreset = .compact
        let target = try geometry(chart)
        let recovered = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
            legacy, chart: chart))
        XCTAssertEqual(recovered, legacy)
        assertSamePoints(ink, project(ink, from: recovered, to: target.space))
    }

    func testDirtyCanvasStyleChangeSaveAndReopenKeepsHandwrittenPitch() throws {
        let chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let original = staffNotation(in: source)
        let originalBytes = original.dataRepresentation()
        let host = try makeHost(chart: chart, mode: .freeHand)
        defer { host.window.isHidden = true }
        host.authoring.drawing = original
        host.view.canvasViewDrawingDidChange(host.authoring)
        attachSyntheticCanvas(host, name: "Synthetic Wide before style change")

        var changed = host.view.chart
        changed.setEngravingPreset(.compact)
        host.view.chart = changed
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let target = try geometry(changed)
        assertStaffPositions(of: original, in: source, match: host.authoring.drawing, in: target)
        attachSyntheticCanvas(host, name: "Synthetic Compact after style change")
        let visible = host.authoring.drawing
        host.view.interactionMode = .browse
        let saved = host.view.chart
        let sourceData = try XCTUnwrap(saved.pageHandwrittenNotationData)
        XCTAssertEqual(sourceData, originalBytes,
            "A style-only change must retain the canonical source drawing archive.")
        let reopenedChart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(saved))
        let reopened = try makeHost(chart: reopenedChart, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSamePoints(visible, reopened.authoring.drawing)
        XCTAssertEqual(reopenedChart.measures, chart.measures)
        XCTAssertEqual(reopenedChart.pageHandwrittenNotationData, originalBytes)
    }

    func testLegacySavedInkLoadedInFreeHandFollowsLaterStyleChangeWithoutRewritingSource() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let original = staffNotation(in: source)
        let originalBytes = original.dataRepresentation()
        var legacy = source.space
        legacy.engravingPreset = nil
        legacy.measureAnchors = legacy.measureAnchors?.map { anchor in
            var anchor = anchor
            anchor.staffFrame = nil
            return anchor
        }
        chart.pageHandwrittenNotationData = originalBytes
        chart.pageHandwrittenNotationCoordinateSpace = legacy
        let host = try makeHost(chart: chart, mode: .freeHand)
        defer { host.window.isHidden = true }
        assertSamePoints(original, host.authoring.drawing)
        XCTAssertEqual(host.view.chart.pageHandwrittenNotationData, originalBytes)
        XCTAssertEqual(host.view.chart.pageHandwrittenNotationCoordinateSpace, legacy)

        // Keep the already-loaded authoring canvas active. Its canonical
        // source must acquire staff metadata when the first style change occurs.
        var changed = host.view.chart
        changed.setEngravingPreset(.compact)
        host.view.chart = changed
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let target = try geometry(changed)
        assertStaffPositions(of: original, in: source, match: host.authoring.drawing, in: target)
        let visible = host.authoring.drawing
        host.view.interactionMode = .browse
        let saved = host.view.chart
        XCTAssertEqual(saved.pageHandwrittenNotationData, originalBytes)
        let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(saved))
        let reopened = try makeHost(chart: decoded, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSamePoints(visible, reopened.authoring.drawing)
        XCTAssertEqual(decoded.pageHandwrittenNotationData, originalBytes)
    }

    func testEraseAndAppendAfterStyleChangePersistActualEditedInkWithoutResurrection() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let original = staffNotation(in: source)
        chart.pageHandwrittenNotationData = original.dataRepresentation()
        chart.pageHandwrittenNotationCoordinateSpace = source.space
        let host = try makeHost(chart: chart, mode: .freeHand)
        defer { host.window.isHidden = true }
        var changed = host.view.chart
        changed.setEngravingPreset(.compact)
        host.view.chart = changed
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let target = try geometry(changed)
        assertStaffPositions(of: original, in: source, match: host.authoring.drawing, in: target)

        let erasedSeed: UInt32 = 11
        let projected = host.authoring.drawing
        XCTAssertTrue(projected.strokes.contains { $0.randomSeed == erasedSeed })
        host.authoring.drawing = PKDrawing(strokes: projected.strokes.filter { $0.randomSeed != erasedSeed })
        host.view.canvasViewDrawingDidChange(host.authoring)
        let firstSystem = try XCTUnwrap(target.staffSystems.first)
        let firstMeasure = try XCTUnwrap(firstSystem.measures.first { $0.sourceMeasureID != nil })
        let spacing = firstSystem.staffLineYPositions[1] - firstSystem.staffLineYPositions[0]
        let x = firstMeasure.staffFrame.minX - target.frame.minX + 24
        let y = firstSystem.staffLineYPositions[0] - target.frame.minY + 1.5 * spacing
        let addedSeed: UInt32 = 99
        let added = stroke([CGPoint(x: x, y: y), CGPoint(x: x + 5, y: y - 2),
            CGPoint(x: x + 8, y: y)], seed: addedSeed)
        host.authoring.drawing = PKDrawing(strokes: host.authoring.drawing.strokes + [added])
        host.view.canvasViewDrawingDidChange(host.authoring)
        let edited = host.authoring.drawing
        let expectedSeeds = edited.strokes.map(\.randomSeed)
        XCTAssertEqual(expectedSeeds.count, original.strokes.count)
        XCTAssertFalse(expectedSeeds.contains(erasedSeed))
        XCTAssertTrue(expectedSeeds.contains(addedSeed))

        host.view.interactionMode = .browse
        let saved = host.view.chart
        let savedDrawing = try PKDrawing(data: XCTUnwrap(saved.pageHandwrittenNotationData))
        assertSamePoints(edited, savedDrawing)
        XCTAssertEqual(savedDrawing.strokes.map(\.randomSeed), expectedSeeds)
        XCTAssertEqual(saved.pageHandwrittenNotationCoordinateSpace?.engravingPreset, .compact,
            "After a real edit the projected canvas becomes the new canonical source.")
        let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(saved))
        let reopened = try makeHost(chart: decoded, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSamePoints(edited, reopened.authoring.drawing)
        assertStaffPositions(of: edited, in: target, match: reopened.authoring.drawing, in: target)
        XCTAssertFalse(reopened.authoring.drawing.strokes.contains { $0.randomSeed == erasedSeed })

        // A further preset change must transform the edited source, including
        // the added note, and must never resurrect the erased original stroke.
        var restoredStyle = reopened.view.chart
        restoredStyle.setEngravingPreset(.wide)
        reopened.view.chart = restoredStyle
        reopened.view.setNeedsLayout()
        reopened.view.layoutIfNeeded()
        let restoredGeometry = try geometry(restoredStyle)
        assertStaffPositions(of: edited, in: target,
            match: reopened.authoring.drawing, in: restoredGeometry)
        XCTAssertEqual(reopened.authoring.drawing.strokes.map(\.randomSeed), expectedSeeds)
        XCTAssertFalse(reopened.authoring.drawing.strokes.contains { $0.randomSeed == erasedSeed })
    }

    func testPassiveCanvasAndSharedPDFInkRendererAgreeAfterEngravingChange() throws {
        var chart = makeChart(.leadSheet, preset: .wide)
        let source = try geometry(chart)
        let original = staffNotation(in: source)
        let bytes = original.dataRepresentation()
        chart.pageHandwrittenNotationData = bytes
        chart.pageHandwrittenNotationCoordinateSpace = source.space
        chart.setEngravingPreset(.compact)
        let target = try geometry(chart)
        let host = try makeHost(chart: chart, mode: .browse)
        defer { host.window.isHidden = true }
        XCTAssertTrue(waitUntil {
            !host.passive.isHidden && host.passive.drawing.strokes.count == original.strokes.count
        })
        let visible = host.passive.drawing
        assertStaffPositions(of: original, in: source, match: visible, in: target)
        let exported = try XCTUnwrap(LeadSheetSavedInkRenderer.renderedInkImage(bytes,
            size: target.space.size, sourceCoordinateSpace: source.space,
            targetCoordinateSpace: target.space, scale: 1))
        let renderedVisible = try XCTUnwrap(LeadSheetSavedInkRenderer.renderedInkImage(visible.dataRepresentation(),
            size: target.space.size, sourceCoordinateSpace: target.space,
            targetCoordinateSpace: target.space, scale: 1))
        XCTAssertEqual(exported.pngData(), renderedVisible.pngData())
        XCTAssertEqual(host.view.chart.pageHandwrittenNotationData, bytes)
        XCTAssertEqual(host.view.chart.pageHandwrittenNotationCoordinateSpace, source.space)
    }

    private struct Geometry {
        var layout: LeadSheetPageLayout
        var frame: CGRect
        var space: PersistentInkCoordinateSpace

        var staffSystems: [LeadSheetSystemLayout] {
            layout.systems.filter { $0.staffLineYPositions.count == 5 }
        }
    }

    private func makeChart(_ style: ChartLayoutStyle, preset: EngravingPreset,
        usesOpenMeasures: Bool = false) -> Chart {
        var chart: Chart
        if usesOpenMeasures {
            // The separate reflow case intentionally exercises open authoring
            // measures, whose packing can change with engraving metrics.
            chart = Chart.draft(title: "Synthetic staff engraving", layoutStyle: style)
            chart.completeInitialSetup(title: chart.title, key: .cMajor,
                meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 8)
            _ = chart.insertSystemBreak(before: chart.measures[4].id)
        } else {
            chart = Chart.blank(title: "Synthetic staff engraving", measureCount: 8, layoutStyle: style)
            let measures = chart.measures
            let spacing = chart.systems[0].spacingMode
            chart.systems = [
                ChartSystem(id: UUID(), index: 0, spacingMode: spacing,
                    lineBreakRule: .automatic, measures: Array(measures.prefix(4))),
                ChartSystem(id: UUID(), index: 1, spacingMode: spacing,
                    lineBreakRule: .forced, measures: Array(measures.suffix(4)))
            ]
            XCTAssertTrue(chart.measures.allSatisfy { $0.authoringState == .committed },
                "The stable-row fixture requires committed measures, rather than open authoring lanes.")
        }
        chart.setEngravingPreset(preset)
        if !usesOpenMeasures {
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
            let actualRows = layout.systems.filter { $0.staffLineYPositions.count == 5 }
                .map { $0.measures.compactMap(\.sourceMeasureID) }
            let authoredRows = chart.systems.map { $0.measures.map(\.id) }
            XCTAssertEqual(actualRows, authoredRows,
                "Stable \(style.rawValue)/\(preset.rawValue) fixture must render the explicit committed 4+4 rows.")
        }
        return chart
    }

    private func geometry(_ chart: Chart, pageSize requestedPageSize: CGSize? = nil) throws -> Geometry {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: requestedPageSize ?? pageSize)
        let frame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        return Geometry(layout: layout, frame: frame,
            space: try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: layout, relativeTo: frame)))
    }

    private func staffNotation(in geometry: Geometry) -> PKDrawing {
        var strokes: [PKStroke] = []
        for (systemIndex, system) in geometry.staffSystems.enumerated() {
            guard let firstMeasure = system.measures.first(where: { $0.sourceMeasureID != nil }) else { continue }
            let line = system.staffLineYPositions[0] - geometry.frame.minY
            let spacing = system.staffLineYPositions[1] - system.staffLineYPositions[0]
            let x = firstMeasure.staffFrame.minX - geometry.frame.minX + 35
            for (noteIndex, step) in [CGFloat(0), 0.5, 2.5, 4, 5].enumerated() {
                let nx = x + CGFloat(noteIndex) * 32
                let y = line + step * spacing
                let seed = UInt32(100 * systemIndex + 10 * noteIndex)
                // Separate notehead, stem, accidental and beam strokes must
                // undergo the same staff transform, including ledger positions.
                strokes.append(stroke([CGPoint(x: nx, y: y), CGPoint(x: nx + 6, y: y - 2),
                    CGPoint(x: nx + 9, y: y), CGPoint(x: nx + 3, y: y + 2), CGPoint(x: nx, y: y)], seed: seed + 1))
                strokes.append(stroke([CGPoint(x: nx + 9, y: y),
                    CGPoint(x: nx + 9, y: y - 2.5 * spacing)], seed: seed + 2))
                strokes.append(stroke([CGPoint(x: nx - 8, y: y - 7),
                    CGPoint(x: nx - 8, y: y + 5), CGPoint(x: nx - 4, y: y)], seed: seed + 3))
                strokes.append(stroke([CGPoint(x: nx + 9, y: y - 2.5 * spacing),
                    CGPoint(x: nx + 17, y: y - 2.3 * spacing)], seed: seed + 4))
            }
        }
        return PKDrawing(strokes: strokes)
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

    private func project(_ drawing: PKDrawing, from source: PersistentInkCoordinateSpace,
        to target: PersistentInkCoordinateSpace) -> PKDrawing {
        LeadSheetPersistentInkCoordinateSpacePolicy.drawing(drawing,
            sourceCoordinateSpace: source, targetCoordinateSpace: target)
    }

    private func assertStaffPositions(of source: PKDrawing, in sourceGeometry: Geometry,
        match target: PKDrawing, in targetGeometry: Geometry, context: String = "",
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(source.strokes.count, target.strokes.count, context, file: file, line: line)
        let sourceRows = sourceGeometry.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
        let targetRows = targetGeometry.staffSystems.map { $0.measures.compactMap(\.sourceMeasureID) }
        guard sourceRows == targetRows else {
            XCTFail("Stable-row fixture unexpectedly reflowed: \(context); source row counts \(sourceRows.map(\.count)), target row counts \(targetRows.map(\.count)). Use the measure-ID reflow oracle for this geometry.",
                file: file, line: line)
            return
        }
        for (before, after) in zip(source.strokes, target.strokes) {
            let systemIndex = Int(before.randomSeed / 100)
            guard sourceGeometry.staffSystems.indices.contains(systemIndex),
                  targetGeometry.staffSystems.indices.contains(systemIndex) else {
                XCTFail("Missing staff system for \(context)", file: file, line: line)
                continue
            }
            let sourceSystem = sourceGeometry.staffSystems[systemIndex]
            let targetSystem = targetGeometry.staffSystems[systemIndex]
            let sourceTop = sourceSystem.staffLineYPositions[0] - sourceGeometry.frame.minY
            let targetTop = targetSystem.staffLineYPositions[0] - targetGeometry.frame.minY
            let sourceSpacing = sourceSystem.staffLineYPositions[1] - sourceSystem.staffLineYPositions[0]
            let targetSpacing = targetSystem.staffLineYPositions[1] - targetSystem.staffLineYPositions[0]
            let sourceSpan = sourceSystem.measures.filter { $0.sourceMeasureID != nil }
                .reduce(CGRect.null) { $0.union($1.staffFrame) }
            let targetSpan = targetSystem.measures.filter { $0.sourceMeasureID != nil }
                .reduce(CGRect.null) { $0.union($1.staffFrame) }
            XCTAssertEqual(before.path.count, after.path.count, context, file: file, line: line)
            for (sourcePoint, targetPoint) in zip(before.path, after.path) {
                let original = sourcePoint.location.applying(before.transform)
                let projected = targetPoint.location.applying(after.transform)
                XCTAssertEqual((projected.x - targetSpan.minX + targetGeometry.frame.minX) / targetSpan.width,
                    (original.x - sourceSpan.minX + sourceGeometry.frame.minX) / sourceSpan.width,
                    accuracy: 0.002, "Handwritten row position changed: \(context), stroke \(before.randomSeed)",
                    file: file, line: line)
                XCTAssertEqual((projected.y - targetTop) / targetSpacing,
                    (original.y - sourceTop) / sourceSpacing, accuracy: 0.002,
                    "Handwritten staff position changed: \(context), stroke \(before.randomSeed)", file: file, line: line)
            }
            XCTAssertEqual(after.randomSeed, before.randomSeed, context, file: file, line: line)
            XCTAssertEqual(after.path.creationDate, before.path.creationDate, context, file: file, line: line)
        }
    }

    private func assertSamePoints(_ source: PKDrawing, _ actual: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(source.strokes.count, actual.strokes.count, file: file, line: line)
        for (before, after) in zip(source.strokes, actual.strokes) {
            XCTAssertEqual(before.randomSeed, after.randomSeed, file: file, line: line)
            assertTransform(after.transform, equals: before.transform, file: file, line: line)
            XCTAssertEqual(before.path.count, after.path.count, file: file, line: line)
            for (sourcePoint, actualPoint) in zip(before.path, after.path) {
                let original = sourcePoint.location.applying(before.transform)
                let projected = actualPoint.location.applying(after.transform)
                XCTAssertEqual(projected.x, original.x, accuracy: 0.01, file: file, line: line)
                XCTAssertEqual(projected.y, original.y, accuracy: 0.01, file: file, line: line)
            }
        }
    }

    private func assertTransform(_ actual: CGAffineTransform, equals expected: CGAffineTransform,
        context: String = "", file: StaticString = #filePath, line: UInt = #line) {
        for (actualComponent, expectedComponent) in zip(
            [actual.a, actual.b, actual.c, actual.d, actual.tx, actual.ty],
            [expected.a, expected.b, expected.c, expected.d, expected.tx, expected.ty]) {
            XCTAssertEqual(actualComponent, expectedComponent, accuracy: 0.00001,
                context, file: file, line: line)
        }
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let authoring: PKCanvasView
        let passive: PKCanvasView
        let window: UIWindow
    }

    private func makeHost(chart: Chart, mode: EditorCanvasMode) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        view.recognizesChordInk = false
        view.chart = chart
        view.interactionMode = mode
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvases = view.subviews.compactMap { $0 as? PKCanvasView }
        return Host(view: view, authoring: try XCTUnwrap(canvases.last),
            passive: try XCTUnwrap(canvases.dropFirst().first), window: window)
    }

    private func attachSyntheticCanvas(_ host: Host, name: String) {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        host.authoring.layoutIfNeeded()
        // PencilKit's offscreen layer is absent from drawHierarchy snapshots.
        // These synthetic composites combine the production staff background
        // with the actual live drawing at its converted canvas bounds. They
        // verify staff/ink geometry and are not physical-device screenshots.
        let inkBounds = host.authoring.bounds
        let inkFrame = host.authoring.convert(inkBounds, to: host.view)
        let inkImage = host.authoring.drawing.image(from: inkBounds, scale: 1)
        let wasHidden = host.authoring.isHidden
        host.authoring.isHidden = true
        defer { host.authoring.isHidden = wasHidden }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(origin: .zero, size: host.view.bounds.size))
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            inkImage.draw(in: inkFrame)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return condition()
    }
}
#endif

import CoreGraphics
import Foundation
import XCTest
@testable import iChart

final class CueTextHorizontalPlacementLayoutTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private let regions: [CueTextHorizontalPlacement.Region] = [.measure, .leadingMargin, .trailingMargin]

    func testNilHorizontalPlacementRetainsLegacyGeometryAfterReopening() throws {
        for style in styles {
            for position in [CuePosition.above, .below] {
                for fraction in [nil as Double?, 0.12345] {
                    var chart = try fixture(style: style)
                    let measureID = chart.measures[1].id
                    let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: measureID, position: position))
                    let index = try XCTUnwrap(chart.cueTexts.firstIndex { $0.id == cueID })
                    chart.cueTexts[index].beatFraction = fraction
                    XCTAssertNil(chart.cueTexts[index].horizontalPlacement)
                    let before = documentPlan(chart)
                    let measure = try measure(measureID, in: before)
                    let cue = try cue(cueID, in: before)
                    let legacyX = fraction.map { fraction in
                        min(max(measure.staffFrame.minX + CGFloat(fraction) * measure.staffFrame.width,
                            measure.staffFrame.minX + 4),
                            max(measure.staffFrame.minX + 4, measure.staffFrame.maxX - cue.frame.width - 4))
                    } ?? measure.staffFrame.minX + 6
                    XCTAssertEqual(cue.frame.minX, legacyX, accuracy: 0.0001)

                    let reopened = try reopen(chart)
                    XCTAssertEqual(reopened.cueText(id: cueID), chart.cueText(id: cueID))
                    XCTAssertNil(reopened.cueText(id: cueID)?.horizontalPlacement)
                    XCTAssertEqual(try self.cue(cueID, in: documentPlan(reopened)), cue)
                    XCTAssertEqual(reopened.cueText(id: cueID)?.beatFraction, fraction)
                }
            }
        }
    }

    func testRepositoryRestoresPlacementAppearanceAndSourceAttachmentsOnTheFixedDocumentPlan() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for style in styles {
            for region in regions {
                var chart = try fixture(style: style)
                chart.setMatchedFontFamily(.petaluma)
                chart.sourcePDFLibraryItemID = UUID()
                chart.pageHandwrittenNotationData = Data([0x31, 0x57, 0x92])
                chart.pageHandwrittenNotationCoordinateSpace = PersistentInkCoordinateSpace(width: 840, height: 1040)
                chart.pageHandwrittenChordData = Data([0x91, 0x72, 0x53])
                let measureID = chart.measures[1].id
                let cueID = try XCTUnwrap(chart.addCueText("  Keep this instruction  ", anchorMeasureID: measureID,
                    position: .below, emphasis: .strong, atFraction: 0.625))
                XCTAssertTrue(chart.updateCueText(cueID, scale: 1.375, verticalOffset: 12.5))
                let placement = CueTextHorizontalPlacement(region: region, fraction: 0.37125)
                XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.625,
                    horizontalPlacement: placement))
                let originalCue = try XCTUnwrap(chart.cueText(id: cueID))
                let before = documentPlan(chart)
                let file = root.appendingPathComponent("\(style.rawValue)-\(region.rawValue).json")
                let repository = FileChartRepository(url: file)
                try repository.saveSnapshot(ChartLibrarySnapshot(charts: [chart], selectedChartID: chart.id,
                    entitlements: .free))

                let restored = try XCTUnwrap(repository.loadSnapshot())
                let reopened = try XCTUnwrap(restored.charts.first)
                XCTAssertEqual(restored.selectedChartID, chart.id)
                XCTAssertEqual(reopened.cueText(id: cueID), originalCue)
                XCTAssertEqual(reopened.cueText(id: cueID)?.horizontalPlacement, placement)
                XCTAssertEqual(reopened.cueText(id: cueID)?.anchorMeasureID, measureID)
                XCTAssertEqual(reopened.documentFont, chart.documentFont)
                XCTAssertEqual(reopened.notationFont, chart.notationFont)
                XCTAssertEqual(reopened.sourcePDFLibraryItemID, chart.sourcePDFLibraryItemID)
                XCTAssertEqual(reopened.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
                XCTAssertEqual(reopened.pageHandwrittenNotationCoordinateSpace, chart.pageHandwrittenNotationCoordinateSpace)
                XCTAssertEqual(reopened.pageHandwrittenChordData, chart.pageHandwrittenChordData)
                XCTAssertEqual(reopened.measures.map(\.chordEvents), chart.measures.map(\.chordEvents))
                XCTAssertEqual(reopened.measures.map(\.rhythmMap), chart.measures.map(\.rhythmMap))
                let after = documentPlan(reopened)
                assertSameStaffPlan(after, before)
                XCTAssertEqual(try cue(cueID, in: after), try cue(cueID, in: before))
                try assertOnOwningPaper(cueID, in: after)
                assertSameStaffPlan(documentPlan(reopened, viewportHeight: 2400), before)
                XCTAssertEqual(try cue(cueID, in: documentPlan(reopened, viewportHeight: 2400)),
                    try cue(cueID, in: before))
            }
        }
    }

    func testMeasurePlacementIsContinuousWhileLegacyBeatFallbackKeepsItsGrid() throws {
        for style in styles {
            var chart = try fixture(style: style)
            let measureID = chart.measures[1].id
            let cueID = try XCTUnwrap(chart.addCueText("Cue", anchorMeasureID: measureID,
                position: .below, atFraction: 0.625))
            var positions: [CGFloat] = []
            var ownerWidth: CGFloat = 0
            for fraction in [0.413, 0.414] {
                XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.417,
                    horizontalPlacement: .init(region: .measure, fraction: fraction)))
                let plan = documentPlan(chart)
                let owner = try measure(measureID, in: plan)
                let displayed = try cue(cueID, in: plan)
                let range = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
                    for: .measure, measureID: measureID, in: plan, cueWidth: displayed.frame.width))
                XCTAssertEqual(range.lowerBound, owner.staffFrame.minX, accuracy: 0.0001)
                XCTAssertEqual(range.upperBound, owner.staffFrame.maxX, accuracy: 0.0001)
                XCTAssertEqual(displayed.frame.minX,
                    owner.staffFrame.minX + owner.staffFrame.width * CGFloat(fraction), accuracy: 0.0001)
                XCTAssertEqual(chart.cueText(id: cueID)?.beatFraction, 0.375)
                positions.append(displayed.frame.minX)
                ownerWidth = owner.staffFrame.width
                try assertOnOwningPaper(cueID, in: plan)
            }
            XCTAssertEqual(positions[1] - positions[0], ownerWidth * 0.001, accuracy: 0.0001,
                "A sub-beat horizontal movement must remain continuous rather than snapping to the beat fallback")
        }
    }

    func testMeasureAndMarginPlacementsFollowTheirOwningRowThroughReflowInBothStyles() throws {
        for style in styles {
            for region in regions {
                for width in [CGFloat(820), 1180] {
                    var chart = try compactFixture(style: style)
                    let measureID = chart.measures[1].id
                    let cueID = try XCTUnwrap(chart.addCueText("Row cue", anchorMeasureID: measureID,
                        position: .below, atFraction: 0.375))
                    let placement = CueTextHorizontalPlacement(region: region, fraction: 0.37125)
                    XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.375,
                        horizontalPlacement: placement))
                    let originalCue = try XCTUnwrap(chart.cueText(id: cueID))
                    let originalMeasureIDs = chart.measures.map(\.id)
                    let before = documentPlan(chart, width: width)
                    let previousOwner = try measure(measureID, in: before)
                    try assertHorizontalPlacement(cueID, placement: placement, owner: measureID, in: before)

                    XCTAssertTrue(chart.insertSystemBreak(before: measureID))
                    let after = documentPlan(chart, width: width)
                    let newSystem = try owningSystem(for: cueID, in: after)
                    XCTAssertEqual(newSystem.measures.compactMap(\.sourceMeasureID).first, measureID)
                    let owner = try measure(measureID, in: after)
                    XCTAssertNotEqual(owner.staffFrame.origin, previousOwner.staffFrame.origin,
                        "The fixture must actually move the owning measure into another row")
                    XCTAssertEqual(chart.measures.map(\.id), originalMeasureIDs)
                    XCTAssertEqual(chart.cueText(id: cueID), originalCue)
                    try assertHorizontalPlacement(cueID, placement: placement, owner: measureID, in: after)
                    try assertOnOwningPaper(cueID, in: after)
                }
            }
        }
    }

    func testOriginRangesUseRealRowEdgesAndRejectUnreadableTrailingMargin() throws {
        for style in styles {
            var chart = try compactFixture(style: style)
            let ownerID = chart.measures[1].id
            let cueID = try XCTUnwrap(chart.addCueText("Margin cue", anchorMeasureID: ownerID,
                position: .below))
            let plan = documentPlan(chart)
            let system = try owningSystem(for: cueID, in: plan)
            let paper = plan.paperFrame(for: system)
            let displayed = try cue(cueID, in: plan)
            let realMeasures = system.measures.filter { $0.sourceMeasureID != nil }
            let leading = try XCTUnwrap(realMeasures.map(\.staffFrame.minX).min())
            let trailing = try XCTUnwrap(realMeasures.map(\.staffFrame.maxX).max())
            let before = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
                for: .leadingMargin, measureID: ownerID, in: plan, cueWidth: displayed.frame.width))
            let after = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
                for: .trailingMargin, measureID: ownerID, in: plan, cueWidth: displayed.frame.width))
            XCTAssertEqual(before.lowerBound, paper.minX + 4, accuracy: 0.0001)
            XCTAssertLessThanOrEqual(before.upperBound, leading + 0.0001)
            XCTAssertEqual(after.lowerBound, trailing, accuracy: 0.0001)
            XCTAssertEqual(after.upperBound + displayed.frame.width, paper.maxX - 4, accuracy: 0.0001)
            XCTAssertNil(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
                for: .trailingMargin, measureID: ownerID, in: plan, cueWidth: paper.width),
                "A trailing placement must not advertise space that cannot hold the readable cue")
            XCTAssertNil(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
                for: .measure, measureID: UUID(), in: plan, cueWidth: displayed.frame.width))
        }
    }

    func testPureVerticalMovementRetainsManualHorizontalPositionWithoutMovingStaves() throws {
        for style in styles {
            for region in regions {
                for density in StaffSystemDensity.allCases {
                    var chart = try compactFixture(style: style)
                    chart.setStaffSystemDensity(density)
                    let measureID = chart.measures[1].id
                    let cueID = try XCTUnwrap(chart.addCueText("Independent axes", anchorMeasureID: measureID,
                        position: .below, atFraction: 0.625))
                    let placement = CueTextHorizontalPlacement(region: region, fraction: 0.413)
                    XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: 0.625,
                        horizontalPlacement: placement))
                    let before = documentPlan(chart)
                    let originalCue = try XCTUnwrap(chart.cueText(id: cueID))
                    let initialFrame = try cue(cueID, in: before).frame
                    for offset in [-8.0, 8.0] {
                        var nudged = chart
                        XCTAssertTrue(nudged.setCueTextVerticalOffset(cueID, to: offset))
                        let after = documentPlan(nudged)
                        let frame = try cue(cueID, in: after).frame
                        assertSameStaffPlan(after, before)
                        XCTAssertEqual(frame.minX, initialFrame.minX, accuracy: 0.0001)
                        XCTAssertEqual(frame.size, initialFrame.size)
                        XCTAssertEqual(nudged.cueText(id: cueID)?.horizontalPlacement, placement)
                        XCTAssertEqual(nudged.cueText(id: cueID)?.beatFraction, originalCue.beatFraction)
                        let travel = frame.minY - initialFrame.minY
                        XCTAssertGreaterThanOrEqual(travel * (offset < 0 ? -1 : 1), -0.001)
                        XCTAssertLessThanOrEqual(abs(travel), abs(offset) + 0.001)
                        try assertOnOwningPaper(cueID, in: after)
                    }
                }
            }
        }
    }

    func testMovingAcrossDifferentMeasureWidthsRetainsTheCapturedWrappingTemplate() throws {
        for style in styles {
            var chart = try compactFixture(style: style)
            let ids = chart.measures.map(\.id)
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(260, for: ids[0]))
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(90, for: ids[1]))
            let cueID = try XCTUnwrap(chart.addCueText("First time softly, then build into the final chorus",
                anchorMeasureID: ids[0], position: .below, emphasis: .strong, atFraction: 0.25))
            XCTAssertTrue(chart.updateCueText(cueID, scale: 1.25))
            let source = documentPlan(chart)
            let template = try cue(cueID, in: source)
            let sourceOwner = try measure(ids[0], in: source)
            let destinationOwner = try measure(ids[1], in: source)
            XCTAssertGreaterThan(sourceOwner.staffFrame.width, destinationOwner.staffFrame.width + 50)
            XCTAssertGreaterThan(template.frame.height, 25, "The fixture must contain a wrapped cue")
            let capturedWrapWidth = max(1, sourceOwner.staffFrame.width - 12)
            let placement = CueTextHorizontalPlacement(region: .measure, fraction: 0.413,
                wrapWidth: Double(capturedWrapWidth))

            XCTAssertTrue(chart.moveCueText(cueID, to: ids[1], atFraction: 0.375, horizontalPlacement: placement))

            let after = documentPlan(chart)
            let moved = try cue(cueID, in: after)
            assertSize(moved.frame.size, equals: template.frame.size)
            XCTAssertEqual(moved.text, template.text)
            XCTAssertEqual(moved.scale, template.scale)
            XCTAssertEqual(moved.emphasis, template.emphasis)
            XCTAssertEqual(chart.cueText(id: cueID)?.horizontalPlacement?.wrapWidth, Double(capturedWrapWidth))
            try assertHorizontalPlacement(cueID, placement: placement, owner: ids[1], in: after)
            try assertOnOwningPaper(cueID, in: after)
            let reopened = try reopen(chart)
            XCTAssertEqual(try cue(cueID, in: documentPlan(reopened)), moved)
        }
    }

    func testCachedHorizontalPreviewMatchesFinalClearSpacePlacementForEveryRegion() throws {
        for style in styles {
            for region in regions {
                var source = try compactFixture(style: style)
                let measureID = source.measures[1].id
                let cueID = try XCTUnwrap(source.addCueText("Cached cue", anchorMeasureID: measureID,
                    position: .below, atFraction: 0.625))
                let sourcePlan = documentPlan(source)
                let sourceCue = try cue(cueID, in: sourcePlan)
                let sourceOwner = try measure(measureID, in: sourcePlan)
                let wrapWidth = Double(max(1, sourceOwner.staffFrame.width - 12))
                let templatePlacement = CueTextHorizontalPlacement(region: region, fraction: 0.5,
                    wrapWidth: wrapWidth)
                let template = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreviewTemplate(chart: source,
                    sourcePageLayout: sourcePlan, cueID: cueID, targetMeasureID: measureID,
                    fraction: 0.625, horizontalPlacement: templatePlacement))
                assertSize(template.frame.size, equals: sourceCue.frame.size)

                for fraction in [0.12345, 0.414, 0.731] {
                    let placement = CueTextHorizontalPlacement(region: region, fraction: fraction,
                        wrapWidth: wrapWidth)
                    let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: source,
                        sourcePageLayout: sourcePlan, cueID: cueID, targetMeasureID: measureID,
                        fraction: 0.625, verticalOffset: 6, horizontalPlacement: placement, template: template))
                    var committed = source
                    XCTAssertTrue(committed.moveCueText(cueID, to: measureID, atFraction: 0.625,
                        verticalOffset: 6, horizontalPlacement: placement))
                    let committedPlan = documentPlan(committed)
                    let final = try cue(cueID, in: committedPlan)

                    assertFrame(preview.frame, equals: final.frame)
                    assertFrame(preview.hitFrame, equals: final.hitFrame)
                    XCTAssertEqual(preview.verticalOffsetFromDefault, final.verticalOffsetFromDefault, accuracy: 0.0001)
                    XCTAssertEqual(preview.text, final.text)
                    XCTAssertEqual(preview.scale, final.scale)
                    XCTAssertEqual(preview.emphasis, final.emphasis)
                    XCTAssertEqual(preview.position, final.position)
                    XCTAssertEqual(preview.beatFraction, final.beatFraction)
                    XCTAssertEqual(final.frame.minY - sourceCue.frame.minY, 6, accuracy: 0.0001)
                    try assertHorizontalPlacement(cueID, placement: placement, owner: measureID, in: committedPlan)
                    assertSameStaffPlan(committedPlan, sourcePlan)
                    try assertOnOwningPaper(cueID, in: committedPlan)
                }
                XCTAssertNil(source.cueText(id: cueID)?.horizontalPlacement,
                    "Projecting cached samples must leave the source chart untouched")
                XCTAssertEqual(try cue(cueID, in: sourcePlan), sourceCue)
            }
        }
    }

    func testExplicitHorizontalTemplateAndFinalGeometryIgnoreLegacyBeatFallback() throws {
        for style in styles {
            var original = try compactFixture(style: style)
            let measureID = original.measures[1].id
            let cueID = try XCTUnwrap(original.addCueText("First pass softly\nThen build", anchorMeasureID: measureID,
                position: .above, emphasis: .strong, atFraction: 0))
            XCTAssertTrue(original.updateCueText(cueID, scale: 1.25))
            _ = try XCTUnwrap(original.addEndingSpan(.ending1, startMeasureID: measureID,
                endMeasureID: original.measures[2].id, displayText: "First pass only"))
            _ = try XCTUnwrap(original.addPointRoadmapMarker(.fine, anchorMeasureID: measureID))
            let placement = CueTextHorizontalPlacement(region: .measure, fraction: 0.413, wrapWidth: 120)
            var baselines: [CGRect] = []
            var frames: [CGRect] = []
            for fallback in [0.0, 0.875] {
                var chart = original
                XCTAssertTrue(chart.moveCueText(cueID, to: measureID, atFraction: fallback,
                    verticalOffset: -5, horizontalPlacement: placement))
                let plan = documentPlan(chart)
                let template = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreviewTemplate(chart: chart,
                    sourcePageLayout: plan, cueID: cueID, targetMeasureID: measureID,
                    fraction: fallback, horizontalPlacement: placement))
                let preview = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextMovePreview(chart: chart,
                    sourcePageLayout: plan, cueID: cueID, targetMeasureID: measureID,
                    fraction: fallback, verticalOffset: -5, horizontalPlacement: placement, template: template))
                let final = try cue(cueID, in: plan)
                assertFrame(preview.frame, equals: final.frame)
                baselines.append(template.frame)
                frames.append(final.frame)
            }
            XCTAssertEqual(baselines[0].minY, baselines[1].minY, accuracy: 0.0001)
            assertSize(baselines[0].size, equals: baselines[1].size)
            assertFrame(frames[0], equals: frames[1])
        }
    }

    private func fixture(style: ChartLayoutStyle) throws -> Chart {
        var chart = Chart.blank(title: "Continuous cue placement", measureCount: 6, layoutStyle: style)
        let measures = chart.measures
        chart.systems = stride(from: 0, to: measures.count, by: 3).enumerated().map { index, start in
            ChartSystem(id: UUID(), index: index, spacingMode: .automatic, lineBreakRule: .forced,
                measures: Array(measures[start..<start + 3]))
        }
        for measure in chart.measures {
            if style == .rhythmSectionSheet {
                XCTAssertTrue(chart.setMeasureRhythmMap([.quarter, .quarter, .quarter, .quarter], for: measure.id))
            }
            _ = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("C7"),
                rawInput: "C7", to: measure.id, atFraction: 0,
                sourceInkData: Data([0x19, 0x37, 0x55]), sourceCandidateSignature: ["C7", "C"]))
        }
        return chart
    }

    private func compactFixture(style: ChartLayoutStyle) throws -> Chart {
        var chart = try fixture(style: style)
        for (index, measure) in chart.measures.enumerated() {
            // Equal manual widths intentionally invoke responsive Equal Row
            // in Rhythm. Use unequal widths to leave genuine margin space.
            XCTAssertNotNil(chart.setMeasureManualLayoutWidth(CGFloat(100 + 5 * (index % 3)), for: measure.id))
        }
        return chart
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        try ChartPersistenceCoders.decoder.decode(Chart.self, from: ChartPersistenceCoders.encoder.encode(chart))
    }

    // Keep the same canonical width and minimum height as ChartPDFRenderer.
    private func documentPlan(_ chart: Chart, width: CGFloat? = nil, viewportHeight: CGFloat = 1100) -> LeadSheetPageLayout {
        let documentWidth = width ?? LeadSheetFreeInkDocumentLayoutPolicy.savedCanvasWidth(for: chart)
            ?? LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth
        return LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: documentWidth, height: viewportHeight))
    }

    private func measure(_ id: UUID, in plan: LeadSheetPageLayout) throws -> LeadSheetMeasureLayout {
        try XCTUnwrap(plan.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
    }

    private func cue(_ id: UUID, in plan: LeadSheetPageLayout) throws -> LeadSheetCueTextLayout {
        try XCTUnwrap(plan.systems.flatMap(\.measures).flatMap(\.cueTextLayouts).first { $0.id == id })
    }

    private func owningSystem(for cueID: UUID, in plan: LeadSheetPageLayout) throws -> LeadSheetSystemLayout {
        try XCTUnwrap(plan.systems.first { $0.measures.flatMap(\.cueTextLayouts).contains { $0.id == cueID } })
    }

    private func assertOnOwningPaper(_ cueID: UUID, in plan: LeadSheetPageLayout,
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let system = try owningSystem(for: cueID, in: plan)
        let paper = try XCTUnwrap(plan.pages.first { $0.systemIDs.contains(system.id) }, file: file, line: line)
        let frame = try cue(cueID, in: plan).frame
        XCTAssertTrue(paper.frame.insetBy(dx: -0.001, dy: -0.001).contains(frame),
            "The complete cue must remain on its actual paper page", file: file, line: line)
    }

    private func assertHorizontalPlacement(_ cueID: UUID, placement: CueTextHorizontalPlacement,
                                           owner: UUID, in plan: LeadSheetPageLayout,
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let displayed = try cue(cueID, in: plan)
        let system = try owningSystem(for: cueID, in: plan)
        let paper = plan.paperFrame(for: system)
        let range = try XCTUnwrap(LeadSheetPageLayoutEngine.cueTextHorizontalOriginRange(
            for: placement.region, measureID: owner, in: plan, cueWidth: displayed.frame.width), file: file, line: line)
        let rawX = range.lowerBound + (range.upperBound - range.lowerBound) * CGFloat(placement.fraction)
        let expectedX = min(max(rawX, paper.minX + 4), max(paper.minX + 4, paper.maxX - 4 - displayed.frame.width))
        XCTAssertEqual(displayed.frame.minX, expectedX, accuracy: 0.0001, file: file, line: line)
    }

    private func assertSize(_ actual: CGSize, equals expected: CGSize,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }

    private func assertFrame(_ actual: CGRect, equals expected: CGRect,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.0001, file: file, line: line)
        assertSize(actual.size, equals: expected.size, file: file, line: line)
    }

    private func measureIDsByPage(_ plan: LeadSheetPageLayout) -> [[UUID]] {
        plan.pages.map { page in
            plan.systems.filter { page.systemIDs.contains($0.id) }.flatMap(\.measures).compactMap(\.sourceMeasureID)
        }
    }

    private func assertSameStaffPlan(_ actual: LeadSheetPageLayout, _ expected: LeadSheetPageLayout,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.pages.map(\.frame), expected.pages.map(\.frame), file: file, line: line)
        XCTAssertEqual(measureIDsByPage(actual), measureIDsByPage(expected), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.frame), expected.systems.map(\.frame), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.staffFrame),
            expected.systems.flatMap(\.measures).map(\.staffFrame), file: file, line: line)
        XCTAssertEqual(actual.systems.flatMap(\.measures).map(\.chordBandFrame),
            expected.systems.flatMap(\.measures).map(\.chordBandFrame), file: file, line: line)
        XCTAssertEqual(actual.systems.map(\.staffLineYPositions), expected.systems.map(\.staffLineYPositions),
            file: file, line: line)
    }
}

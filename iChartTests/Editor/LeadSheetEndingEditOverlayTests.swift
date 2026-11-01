#if canImport(UIKit)
import CoreGraphics
import Foundation
import UIKit
import XCTest
@testable import iChart

@MainActor
final class LeadSheetEndingEditOverlayTests: XCTestCase {
    func testEveryContinuationHasMoveAndOnlyTheTrueLastSegmentHasLengthenEvenWhenOpen() throws {
        for style in ChartLayoutStyle.allCases {
            let fixture = try fixture(style: style, measureCount: 12, start: 0, end: 11, endStyle: .open)
            let segments = fixture.layout.systems.flatMap(\.endingLayouts).filter { $0.roadmapObjectID == fixture.id }
            XCTAssertGreaterThan(segments.count, 1, style.rawValue)
            let controls = LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout)
            XCTAssertEqual(controls.count, segments.count)
            XCTAssertEqual(controls.compactMap(\.lengthenHandle).count, 1)
            XCTAssertEqual(controls.last?.systemIndex, segments.map(\.systemIndex).max())
            XCTAssertNotNil(controls.last?.lengthenHandle)
            XCTAssertTrue(segments.allSatisfy { !$0.showsTrailingHook })
            for control in controls {
                XCTAssertEqual(control.moveAttachment.x, control.segmentFrame.minX)
                XCTAssertTrue(control.paperFrame.contains(control.moveHandle))
                if let length = control.lengthenHandle {
                    XCTAssertEqual(control.lengthAttachment?.x, control.segmentFrame.maxX)
                    XCTAssertTrue(control.paperFrame.contains(length))
                    XCTAssertFalse(control.moveHandle.intersects(length))
                }
            }
        }
    }

    func testShortBracketHandlesStaySeparateInsidePaperAndKeep44ScreenPointsAtEveryZoom() throws {
        let fixture = try fixture()
        let systemIndex = try XCTUnwrap(fixture.layout.systems.firstIndex { !$0.endingLayouts.isEmpty })
        let paper = fixture.layout.paperFrame(for: fixture.layout.systems[systemIndex])
        for scale: CGFloat in [0.5, 1, 2] {
            for x in [paper.minX + 2, paper.midX, paper.maxX - 5] {
                var layout = fixture.layout
                layout.systems[systemIndex].endingLayouts[0].frame.origin.x = x
                layout.systems[systemIndex].endingLayouts[0].frame.size.width = 3
                let controls = try XCTUnwrap(LeadSheetEndingEditOverlay.controlFrames(
                    for: fixture.id, in: layout, screenPointsPerDisplayedPoint: scale).first)
                let length = try XCTUnwrap(controls.lengthenHandle)
                XCTAssertFalse(controls.moveHandle.intersects(length))
                for frame in [controls.moveHandle, length] {
                    XCTAssertGreaterThanOrEqual(frame.width * scale, 44 - 0.001)
                    XCTAssertGreaterThanOrEqual(frame.height * scale, 44 - 0.001)
                    XCTAssertTrue(paper.contains(frame), "Controls must remain on their paper page")
                }
                var selection = RenderedEditSelectionState()
                selection.select(.endingSpan(fixture.id))
                let context = RenderedEditContext(pageLayout: layout, selection: selection,
                    screenPointsPerDisplayedPoint: scale)
                let targets = EndingSpanRenderedEditHitTargetProvider().hitTargets(in: context)
                XCTAssertEqual(targets.first { $0.action == .move }?.frame, controls.moveHandle)
                XCTAssertEqual(targets.first { $0.action == .resizeTrailing }?.frame, length)
                XCTAssertEqual(RenderedEditRouter().dragTarget(at: center(controls.moveHandle), in: context)?.action, .move)
                XCTAssertEqual(RenderedEditRouter().dragTarget(at: center(length), in: context)?.action, .resizeTrailing)
            }
        }
        let ordinary = LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout)
        for invalid: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertEqual(LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout,
                screenPointsPerDisplayedPoint: invalid), ordinary)
        }
    }

    func testFirstTapSelectsSecondBodyTapEditsAndOnlySelectedVisibleControlsCanDrag() throws {
        let fixture = try fixture()
        let segment = try XCTUnwrap(fixture.layout.systems.flatMap(\.endingLayouts).first)
        let location = CGPoint(x: segment.frame.midX, y: segment.frame.minY + 3)
        let router = RenderedEditRouter()
        let unselected = RenderedEditContext(pageLayout: fixture.layout)
        XCTAssertEqual(router.tapTarget(at: location, in: unselected)?.action, .select)
        XCTAssertNil(router.dragTarget(at: location, in: unselected))
        XCTAssertFalse(EndingSpanRenderedEditHitTargetProvider().hitTargets(in: unselected).contains {
            $0.action.isMove || $0.action.isResize
        })
        var selection = RenderedEditSelectionState()
        selection.select(.endingSpan(fixture.id))
        let selected = RenderedEditContext(pageLayout: fixture.layout, selection: selection)
        XCTAssertEqual(router.tapTarget(at: location, in: selected)?.action, .openInspector)
        XCTAssertNil(router.dragTarget(at: location, in: selected), "The bracket body remains an edit target, not a hidden drag region")
        let controls = try XCTUnwrap(LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout).first)
        for (frame, action) in [(controls.moveHandle, RenderedEditAction.move),
                                (try XCTUnwrap(controls.lengthenHandle), .resizeTrailing)] {
            let target = try XCTUnwrap(router.dragTarget(at: center(frame), in: selected))
            XCTAssertEqual(target.objectID, .endingSpan(fixture.id))
            XCTAssertEqual(target.action, action)
            XCTAssertEqual(target.frame, frame)
            XCTAssertTrue(target.requiresSelection)
            XCTAssertGreaterThan(target.priority, .objectBodySelect)
            XCTAssertEqual(target.mutationRisk, .structural)
            XCTAssertEqual(router.tapTarget(at: center(frame), in: selected)?.action, .select,
                "A short tap on a drag chip must not open an unrelated object underneath it")
        }
    }

    func testControlsAvoidNeighborEndingBodiesWhenAnOpenBandIsAvailable() throws {
        var fixture = try fixture(start: 0, end: 3)
        let ids = fixture.chart.measures.map(\.id)
        let neighbor = try XCTUnwrap(fixture.chart.addEndingSpan(.ending1,
            startMeasureID: ids[0], endMeasureID: ids[3], displayText: "Last time", endStyle: .open))
        fixture.layout = LeadSheetPageLayoutEngine.pageLayout(for: fixture.chart, pageSize: fixture.layout.pageBounds.size)
        let controls = LeadSheetEndingEditOverlay.controlFrames(for: neighbor, in: fixture.layout)
        for control in controls {
            let otherBodies = fixture.layout.systems.filter { $0.index == control.systemIndex }
                .flatMap(\.endingLayouts).filter { $0.roadmapObjectID != neighbor }
                .map { $0.occupiedFrame.insetBy(dx: -6, dy: -8) }
            for frame in [control.moveHandle] + (control.lengthenHandle.map { [$0] } ?? []) {
                XCTAssertTrue(otherBodies.allSatisfy { !frame.intersects($0) })
            }
        }
    }

    func testGhostRetainsProductionBracketShapeAndSourceStaffAnchorsWithoutMutatingTheChart() throws {
        let fixture = try fixture(measureCount: 12, start: 0, end: 3, endStyle: .open)
        let original = fixture.chart
        var preview = fixture.chart
        let ids = preview.measures.map(\.id)
        XCTAssertTrue(preview.updateEndingDetails(fixture.id, startMeasureID: ids[4], endMeasureID: ids[9],
            displayText: "1–3, 5", endStyle: .open))
        let previewLayout = LeadSheetPageLayoutEngine.pageLayout(for: preview, pageSize: fixture.layout.pageBounds.size)
        let ghosts = LeadSheetEndingEditOverlay.previewSegments(for: fixture.id, previewChart: preview, sourceLayout: fixture.layout)
        XCTAssertGreaterThan(ghosts.count, 1)
        XCTAssertEqual(ghosts.map(\.systemIndex), previewLayout.systems.filter {
            $0.endingLayouts.contains { $0.roadmapObjectID == fixture.id }
        }.map(\.index))
        for ghost in ghosts {
            let sourceSystem = try XCTUnwrap(fixture.layout.systems.first { $0.index == ghost.systemIndex })
            let previewSystem = try XCTUnwrap(previewLayout.systems.first { $0.index == ghost.systemIndex })
            let rendered = try XCTUnwrap(previewSystem.endingLayouts.first { $0.roadmapObjectID == fixture.id })
            let sourceY = try XCTUnwrap(sourceSystem.measures.first?.staffFrame.minY)
            let previewY = try XCTUnwrap(previewSystem.measures.first?.staffFrame.minY)
            XCTAssertEqual(ghost.frame.maxY - sourceY, rendered.frame.maxY - previewY, accuracy: 0.001)
            XCTAssertEqual(ghost.showsLeadingHook, rendered.showsLeadingHook)
            XCTAssertEqual(ghost.showsTrailingHook, rendered.showsTrailingHook)
            XCTAssertEqual(ghost.text, rendered.text)
        }
        XCTAssertEqual(fixture.chart, original)
    }

    func testPlacementKeepsChipsClearOfTheHeaderAndPreviousRowGlyphsAtEveryZoom() throws {
        let fixture = try fixture(measureCount: 12, start: 0, end: 11, endStyle: .open, populated: true)
        XCTAssertFalse(fixture.layout.systems.flatMap(\.measures).flatMap(\.chordLayouts).isEmpty)
        for scale: CGFloat in [0.5, 1, 2] {
            let obstacles = LeadSheetEndingOverlayPlacement.notationObstacles(in: fixture.layout, scale: scale)
            let controls = LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout,
                screenPointsPerDisplayedPoint: scale)
            XCTAssertEqual(controls.count, fixture.layout.systems.flatMap(\.endingLayouts).count)
            var allFrames: [CGRect] = []
            for control in controls {
                let frames = [control.moveHandle] + (control.lengthenHandle.map { [$0] } ?? [])
                for frame in frames {
                    XCTAssertFalse(frame.intersects(fixture.layout.header.frame), "Header occlusion at zoom \(scale)")
                    XCTAssertTrue(obstacles.allSatisfy { !frame.intersects($0) }, "A control covered notation at zoom \(scale)")
                    XCTAssertTrue(allFrames.allSatisfy { !frame.intersects($0) })
                    XCTAssertGreaterThanOrEqual(frame.height * scale, 44 - 0.001)
                    XCTAssertGreaterThanOrEqual(frame.width * scale, 44 - 0.001)
                    allFrames.append(frame)
                }
            }
        }
    }

    func testMoveAndLengthenFeedbackAppearImmediatelyWithTheirActionAndMeasureCount() throws {
        let fixture = try fixture(start: 1, end: 1, populated: true)
        let original = fixture.chart
        let sourceRow = try XCTUnwrap(fixture.layout.systems.first { !$0.endingLayouts.isEmpty }).index
        for action in [RenderedEditAction.move, .resizeTrailing] {
            let feedback = LeadSheetEndingDragFeedback(action: action, range: 1...1, sourceSystemIndex: sourceRow)
            for scale: CGFloat in [0.5, 1, 2] {
                let display = LeadSheetEndingEditOverlay.presentation(for: fixture.id, chart: fixture.chart,
                    pageLayout: fixture.layout, screenPointsPerDisplayedPoint: scale, dragFeedback: feedback)
                XCTAssertTrue(display.isDragging)
                XCTAssertFalse(display.candidateSegments.isEmpty, "The initial ending must remain visible when Host fades its source")
                XCTAssertEqual(display.coverage.map(\.measureIndex), [1])
                let callout = try XCTUnwrap(display.callout)
                XCTAssertEqual(callout.title, action == .move ? "Move ending" : "Adjust length")
                XCTAssertEqual(callout.rangeText, "Measure 2 · 1 measure")
                XCTAssertEqual(callout.instruction, action == .move ? "Release to place" : "Release to set length")
                let frames = display.controls.flatMap { [$0.moveHandle] + ($0.lengthenHandle.map { [$0] } ?? []) }
                XCTAssertTrue(frames.allSatisfy { !callout.frame.intersects($0) })
                XCTAssertFalse(callout.frame.intersects(fixture.layout.header.frame))
                let paper = try XCTUnwrap(display.controls.first?.paperFrame)
                XCTAssertTrue(paper.contains(callout.frame))
            }
        }
        XCTAssertEqual(fixture.chart, original)
    }

    func testMoveFeedbackFollowsTheGrabbedContinuationAndLengthenFollowsTheNewEndpoint() throws {
        let fixture = try fixture(measureCount: 16, start: 0, end: 7, endStyle: .open, populated: true)
        let originalControls = LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout)
        XCTAssertEqual(originalControls.count, 2)
        let sourceRow = try XCTUnwrap(originalControls.last?.systemIndex)
        var moved = fixture.chart
        let ids = moved.measures.map(\.id)
        XCTAssertTrue(moved.updateEndingDetails(fixture.id, startMeasureID: ids[4], endMeasureID: ids[11],
            displayText: "1–3, 5", endStyle: .open))
        let moving = LeadSheetEndingEditOverlay.presentation(for: fixture.id, chart: fixture.chart,
            pageLayout: fixture.layout, previewChart: moved,
            dragFeedback: .init(action: .move, range: 4...11, sourceSystemIndex: sourceRow))
        XCTAssertEqual(moving.activeMoveSystemIndex, 2)
        XCTAssertEqual(moving.rangeCaption, "Bars 5–12", "The active capsule must retain numeric feedback when a separate card cannot fit")
        let activeMove = try XCTUnwrap(moving.controls.first { $0.systemIndex == moving.activeMoveSystemIndex })
        XCTAssertEqual(activeMove.systemIndex, 2, "The active control follows the grabbed continuation independently of optional status")
        if moving.callout == nil {
            try attachPlacementDiagnostics(fixture: fixture, display: moving, activeControl: activeMove)
        }
        let moveCallout = try XCTUnwrap(moving.callout,
            "The populated fixture has a 66-point inter-row gap for a 52-point card with six total points of padding on each side")
        XCTAssertEqual(moveCallout.systemIndex, 2, "Status must accompany the grabbed continuation, not the offscreen first segment")
        XCTAssertEqual(moveCallout.rangeText, "Measures 5–12 · 8 measures")
        let preferred = CGPoint(x: activeMove.moveHandle.midX - moveCallout.frame.width / 2,
            y: activeMove.moveHandle.minY - moveCallout.frame.height - 8)
        XCTAssertEqual(moveCallout.frame.height, 52, accuracy: 0.001)
        XCTAssertLessThanOrEqual(hypot(moveCallout.frame.minX - preferred.x, moveCallout.frame.minY - preferred.y), 240)
        XCTAssertEqual(moving.coverage.map(\.measureIndex), Array(4...11))
        XCTAssertEqual(moving.controls.last?.lengthAttachment?.x, moving.candidateSegments.last?.frame.maxX)
        var lengthened = fixture.chart
        XCTAssertTrue(lengthened.updateEndingDetails(fixture.id, startMeasureID: ids[0], endMeasureID: ids[14],
            displayText: "1–3, 5", endStyle: .open))
        let resizing = LeadSheetEndingEditOverlay.presentation(for: fixture.id, chart: fixture.chart,
            pageLayout: fixture.layout, previewChart: lengthened,
            dragFeedback: .init(action: .resizeTrailing, range: 0...14, sourceSystemIndex: sourceRow))
        if let callout = resizing.callout {
            XCTAssertEqual(callout.systemIndex, resizing.controls.last?.systemIndex)
            XCTAssertEqual(callout.rangeText, "Measures 1–15 · 15 measures")
        }
        XCTAssertEqual(resizing.controls.last?.lengthAttachment?.x, resizing.candidateSegments.last?.frame.maxX)
        XCTAssertEqual(resizing.rangeCaption, "Bars 1–15")
        XCTAssertEqual(LeadSheetEndingEditOverlay.controlFrames(for: fixture.id, in: fixture.layout), originalControls,
            "Candidate presentation must not rewrite the frozen source begin/hit geometry")
    }

    func testCrowdedLeadAndRhythmLayoutsKeepEssentialHandlesButHideAnOccludingStatusCard() throws {
        for style in [ChartLayoutStyle.leadSheet, .rhythmSectionSheet] {
            let fixture = try fixture(style: style, populated: true)
            var crowded = fixture.layout
            let paper = crowded.paperFrame(for: crowded.systems[0])
            // A synthetic full-page occupied navigation box makes the lack
            // of a free slot explicit, independent of font wrapping details.
            crowded.systems[0].roadmapTextFrame = paper
            for scale: CGFloat in [0.5, 1, 2] {
                let display = LeadSheetEndingEditOverlay.presentation(for: fixture.id, chart: fixture.chart,
                    pageLayout: crowded, screenPointsPerDisplayedPoint: scale,
                    dragFeedback: .init(action: .move, range: 1...2, sourceSystemIndex: 0))
                XCTAssertFalse(display.controls.isEmpty)
                XCTAssertFalse(display.candidateSegments.isEmpty)
                XCTAssertFalse(display.coverage.isEmpty)
                XCTAssertNil(display.callout, "Optional status must not cover a fully occupied page")
                XCTAssertEqual(display.rangeCaption, "Bars 2–3", "The active capsule retains the range when the larger card is hidden")
                var frames: [CGRect] = []
                for control in display.controls {
                    for frame in [control.moveHandle] + (control.lengthenHandle.map { [$0] } ?? []) {
                        XCTAssertTrue(paper.contains(frame))
                        XCTAssertGreaterThanOrEqual(frame.width * scale, 44 - 0.001)
                        XCTAssertGreaterThanOrEqual(frame.height * scale, 44 - 0.001)
                        XCTAssertTrue(frames.allSatisfy { !frame.intersects($0) })
                        frames.append(frame)
                    }
                }
            }
        }
    }

    func testOptionalStatusStaysNearbyOrHidesInsteadOfJumpingToThePageBottom() {
        for scale: CGFloat in [0.5, 1, 2] {
            let paper = CGRect(x: 0, y: 0, width: 500 / scale, height: 1000 / scale)
            let size = CGSize(width: 100 / scale, height: 52 / scale)
            let preferred = CGPoint(x: 20 / scale, y: 20 / scale)
            let occupied = CGRect(x: 0, y: 0, width: 500 / scale, height: 600 / scale)
            XCTAssertNotNil(LeadSheetEndingOverlayPlacement.frame(size: size, preferredOrigin: preferred,
                inside: paper, obstacles: [occupied], reserved: [], scale: scale, requiresClearSpace: true))
            XCTAssertNil(LeadSheetEndingOverlayPlacement.frame(size: size, preferredOrigin: preferred,
                inside: paper, obstacles: [occupied], reserved: [], scale: scale,
                requiresClearSpace: true, maximumScreenOriginTravel: 240),
                "A free slot far down the page cannot substitute for nearby drag feedback")
        }
    }

    func testSyntheticNativeCanvasAndGhostSnapshotsMatchVisibleHandleTargets() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let one = try fixture(start: 1, end: 1)
        let multi = try fixture(measureCount: 12, start: 0, end: 11, endStyle: .open, populated: true)
        let moveSource = try fixture(measureCount: 16, start: 0, end: 7, endStyle: .open, populated: true)
        var moved = moveSource.chart
        let moveIDs = moved.measures.map(\.id)
        XCTAssertTrue(moved.updateEndingDetails(moveSource.id, startMeasureID: moveIDs[4], endMeasureID: moveIDs[11],
            displayText: "1–3, 5", endStyle: .open))
        var preview = one.chart
        let ids = preview.measures.map(\.id)
        XCTAssertTrue(preview.updateEndingDetails(one.id, startMeasureID: ids[1], endMeasureID: ids[3],
            displayText: "1–3, 5", endStyle: .closed))
        XCTAssertEqual(preview.roadmapObject(id: one.id)?.startMeasureID,
            one.chart.roadmapObject(id: one.id)?.startMeasureID,
            "The Lengthen visual proof must preserve the ending's start measure")
        let beginMove = LeadSheetEndingDragFeedback(action: .move, range: 1...1, sourceSystemIndex: 0)
        let beginLength = LeadSheetEndingDragFeedback(action: .resizeTrailing, range: 1...1, sourceSystemIndex: 0)
        let cases: [(String, Fixture, CGFloat, Chart?, LeadSheetEndingDragFeedback?)] = [
            ("ending-edit-one-measure-native", one, 1, nil, nil),
            ("ending-edit-one-measure-half-zoom-native", one, 0.5, nil, nil),
            ("ending-edit-open-multirow-native", multi, 1, nil, nil),
            ("ending-edit-lengthened-ghost", one, 1, preview,
                .init(action: .resizeTrailing, range: 1...3, sourceSystemIndex: 0)),
            ("ending-edit-move-immediate", one, 1, nil, beginMove),
            ("ending-edit-length-immediate-half-zoom", one, 0.5, nil, beginLength),
            ("ending-edit-moved-continuation", moveSource, 1, moved,
                .init(action: .move, range: 4...11, sourceSystemIndex: 1))
        ]
        for (name, fixture, scale, preview, feedback) in cases {
            let image = raster(fixture, scale: scale, previewChart: preview, feedback: feedback)
            let png = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(png.count, 5_000)
            let display = LeadSheetEndingEditOverlay.presentation(for: fixture.id, chart: fixture.chart,
                pageLayout: fixture.layout, previewChart: preview, screenPointsPerDisplayedPoint: scale,
                dragFeedback: feedback)
            for control in display.controls {
                for frame in [control.moveHandle] + (control.lengthenHandle.map { [$0] } ?? []) {
                    let onScreen = frame.applying(CGAffineTransform(scaleX: scale, y: scale))
                    XCTAssertGreaterThan(try bluePixelCount(in: image, region: onScreen), 20, name)
                }
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let path = environment("ICHART_ENDING_EDIT_QA_OUTPUT") {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try png.write(to: directory.appendingPathComponent(name + ".png"))
            }
        }
    }

    private struct Fixture {
        var chart: Chart
        var layout: LeadSheetPageLayout
        var id: UUID
    }

    private func attachPlacementDiagnostics(
        fixture: Fixture, display: LeadSheetEndingEditOverlay.Presentation,
        activeControl: LeadSheetEndingEditOverlay.SegmentControls
    ) throws {
        let scale: CGFloat = 1
        let paper = activeControl.paperFrame
        let size = CGSize(width: min(246, paper.width - 12), height: 52)
        let preferred = CGPoint(x: activeControl.moveHandle.midX - size.width / 2,
            y: activeControl.moveHandle.minY - size.height - 8)
        let obstacles = LeadSheetEndingOverlayPlacement.notationObstacles(in: fixture.layout, scale: scale)
            + display.candidateSegments.map { $0.occupiedFrame.insetBy(dx: -3, dy: -3) }
        let reserved = display.controls.flatMap { [$0.moveHandle] + ($0.lengthenHandle.map { [$0] } ?? []) }
        let usable = paper.insetBy(dx: 6, dy: 6)
        let blocked = obstacles.filter { $0.intersects(usable) }
        let hard = reserved.filter { $0.intersects(usable) }.map { $0.insetBy(dx: -3, dy: -3) }
        let nearest = (blocked + hard).enumerated().sorted {
            let lhs = hypot($0.element.minX - preferred.x, $0.element.minY - preferred.y)
            let rhs = hypot($1.element.minX - preferred.x, $1.element.minY - preferred.y)
            return lhs < rhs
        }.prefix(12)
        var xs = [preferred.x, usable.minX, usable.maxX - size.width, usable.midX - size.width / 2]
        var ys = [preferred.y, usable.minY, usable.maxY - size.height, usable.midY - size.height / 2]
        for entry in nearest {
            xs += [entry.element.minX - 3 - size.width, entry.element.maxX + 3]
            ys += [entry.element.minY - 3 - size.height, entry.element.maxY + 3]
        }
        func coordinates(_ values: [CGFloat], lower: CGFloat, upper: CGFloat) -> [CGFloat] {
            var result: [CGFloat] = []
            for value in values where value.isFinite {
                let value = min(max(value, lower), upper)
                if !result.contains(where: { abs($0 - value) < 0.5 }) { result.append(value) }
                if result.count == 32 { break }
            }
            return result
        }
        let best = LeadSheetEndingOverlayPlacement.frame(size: size, preferredOrigin: preferred,
            inside: paper, obstacles: obstacles, reserved: reserved, scale: 1,
            requiresClearSpace: false, maximumScreenOriginTravel: 240, clearanceScreenPoints: 3)
        let report: [String: Any] = [
            "syntheticOnly": true, "scale": 1,
            "paper": rect(paper), "usablePaper": rect(usable),
            "calloutSize": ["width": size.width, "height": size.height],
            "preferredOrigin": ["x": preferred.x, "y": preferred.y],
            "maximumScreenOriginTravel": 240, "clearanceScreenPoints": 3, "coordinateLimit": 32,
            "activeSystemIndex": activeControl.systemIndex,
            "activeMove": rect(activeControl.moveHandle),
            "controls": display.controls.map { control -> [String: Any] in
                ["system": control.systemIndex, "segment": rect(control.segmentFrame),
                 "move": rect(control.moveHandle), "lengthen": control.lengthenHandle.map(rect) as Any? ?? NSNull()]
            },
            "header": rect(fixture.layout.header.frame),
            "systems": fixture.layout.systems.map { system -> [String: Any] in
                ["index": system.index, "frame": rect(system.frame),
                 "sourceEndings": system.endingLayouts.map { ending -> [String: Any] in
                     ["frame": rect(ending.frame), "occupied": rect(ending.occupiedFrame), "label": rect(ending.labelFrame)]
                 },
                 "measures": system.measures.map { measure -> [String: Any] in
                     ["index": measure.index, "frame": rect(measure.frame), "staff": rect(measure.staffFrame),
                      "trailingBarline": rect(measure.trailingBarlineFrame),
                      "chords": measure.chordLayouts.map { ["frame": rect($0.frame), "natural": rect($0.naturalFrame)] }]
                 }]
            },
            "candidateEndings": display.candidateSegments.map { ending -> [String: Any] in
                ["system": ending.systemIndex, "frame": rect(ending.frame),
                 "occupied": rect(ending.occupiedFrame), "label": rect(ending.labelFrame)]
            },
            "notationObstacles": obstacles.map(rect), "reservedHandles": reserved.map(rect),
            "nearestTwelve": nearest.map { entry -> [String: Any] in
                ["combinedIndex": entry.offset, "frame": rect(entry.element)]
            },
            "candidateXs": coordinates(xs, lower: usable.minX, upper: usable.maxX - size.width),
            "candidateYs": coordinates(ys, lower: usable.minY, upper: usable.maxY - size.height),
            "bestNearbyAllowingOverlap": best.map(rect) as Any? ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Synthetic ending placement diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = environment("ICHART_ENDING_EDIT_QA_OUTPUT") {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent("ending-placement-diagnostics.json"))
        }
    }

    private func rect(_ frame: CGRect) -> [String: CGFloat] {
        ["x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height]
    }

    private func fixture(
        style: ChartLayoutStyle = .simpleChordSheet, measureCount: Int = 4,
        start: Int = 1, end: Int = 2, endStyle: EndingEndStyle = .closed, populated: Bool = false
    ) throws -> Fixture {
        var chart = Chart.blank(title: "Ending edit controls", measureCount: measureCount, layoutStyle: style)
        chart.stylePreset = .plainWhite
        let ids = chart.measures.map(\.id)
        if measureCount >= 12 && style != .leadSheet {
            for index in stride(from: 4, to: measureCount, by: 4) {
                XCTAssertTrue(chart.insertSystemBreak(before: ids[index]))
            }
        }
        if populated {
            let names = ["C", "Dm7", "G7", "Cmaj7"]
            for (index, id) in ids.enumerated() {
                let match = try XCTUnwrap(ChordRecognitionCompendium.match(names[index % names.count]))
                XCTAssertNotNil(chart.appendRecognizedChordEvent(match.symbol, rawInput: match.displayText,
                    to: id, atFraction: 0.22))
            }
        }
        let id = try XCTUnwrap(chart.addEndingSpan(.ending1, startMeasureID: ids[start], endMeasureID: ids[end],
            displayText: "1–3, 5", endStyle: endStyle))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
        return Fixture(chart: chart, layout: layout, id: id)
    }

    private func raster(_ fixture: Fixture, scale: CGFloat, previewChart: Chart?, feedback: LeadSheetEndingDragFeedback?) -> UIImage {
        let size = fixture.layout.pageBounds.size
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: size))
        canvas.recognizesChordInk = false
        canvas.chart = fixture.chart
        canvas.interactionMode = .browse
        canvas.selectedEndingSpanID = previewChart == nil && feedback == nil ? fixture.id : nil
        canvas.overrideUserInterfaceStyle = .light
        let window = UIWindow(frame: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        window.addSubview(canvas)
        canvas.transform = CGAffineTransform(scaleX: scale, y: scale)
        canvas.frame.origin = .zero
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let actualScale = hypot(canvas.convert(CGPoint(x: 1, y: 0), to: window).x - canvas.convert(.zero, to: window).x,
            canvas.convert(CGPoint(x: 1, y: 0), to: window).y - canvas.convert(.zero, to: window).y)
        XCTAssertEqual(actualScale, scale, accuracy: 0.001)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(window.bounds)
            context.cgContext.scaleBy(x: scale, y: scale)
            canvas.draw(canvas.bounds)
            if previewChart != nil || feedback != nil {
                // Active artifacts exercise the pure presentation over a native
                // page. Fade only its dedicated source-ending band to mirror
                // Host's separate drawEnding alpha gate (not a live pan).
                UIColor.white.withAlphaComponent(0.82).setFill()
                for ending in fixture.layout.systems.flatMap(\.endingLayouts) where ending.roadmapObjectID == fixture.id {
                    UIBezierPath(rect: ending.occupiedFrame.insetBy(dx: -2, dy: -2)).fill()
                }
                LeadSheetEndingEditOverlay.draw(endingID: fixture.id, chart: fixture.chart,
                    pageLayout: fixture.layout, previewChart: previewChart, screenPointsPerDisplayedPoint: scale,
                    dragFeedback: feedback)
            }
        }
    }

    private func bluePixelCount(in image: UIImage, region: CGRect) throws -> Int {
        let image = try XCTUnwrap(image.cgImage?.cropping(to: region.integral))
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        XCTAssertTrue(didDraw)
        var count = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let red = Int(pixels[index])
            let blue = Int(pixels[index + 2])
            if blue > red + 45 && blue > 120 { count += 1 }
        }
        return count
    }

    private func center(_ frame: CGRect) -> CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    private func environment(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_\(key)"]
    }
}
#endif

#if canImport(UIKit)
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CueTextHitRoutingTests: XCTestCase {
    func testControlHitRegionsKeepVerticalPaddingAndNeverBorrowAnotherAction() throws {
        let cue = text(frame: CGRect(x: 100, y: 200, width: 70, height: 24))
        let visible = controls(LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cue))
        let hits = controls(LeadSheetCueTextEditOverlayGeometry.controlHitFrames(for: cue))
        for (index, region) in hits.enumerated() {
            XCTAssertTrue(region.frame.contains(visible[index].frame))
            XCTAssertEqual(region.frame.minY, visible[index].frame.minY - 7)
            XCTAssertEqual(region.frame.maxY, visible[index].frame.maxY + 7)
            for other in hits.indices where other != index {
                XCTAssertFalse(region.frame.intersects(hits[other].frame))
            }
        }
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let context = context(cues: [cue], selected: cue.id, style: style)
            let router = RenderedEditRouter(providers: [CueTextRenderedEditHitTargetProvider()])
            for region in hits {
                for x in [region.frame.minX + 0.25, region.frame.midX, region.frame.maxX - 0.25] {
                    for y in [region.frame.minY + 0.25, region.frame.midY, region.frame.maxY - 0.25] {
                        let point = CGPoint(x: x, y: y)
                        XCTAssertEqual(router.tapTarget(at: point, in: context)?.action, region.action)
                        let legacy = LeadSheetCueTextEditOverlayGeometry.hitTarget(at: point,
                            in: [cue], selectedCueTextID: cue.id)
                        XCTAssertEqual(action(legacy?.action), region.action)
                        XCTAssertNil(router.dragTarget(at: point, in: context),
                            "The edit button's padding must not begin a body move")
                    }
                }
            }
            // Previously this visible edge of + also hit X's destructive halo.
            let grow = visible[2].frame
            let edge = CGPoint(x: grow.maxX - 0.25, y: grow.midY)
            XCTAssertEqual(router.tapTarget(at: edge, in: context)?.action, .grow)
        }
    }

    func testVisibleCueWinsOverAnotherCuesBodyPaddingRegardlessOfArrayOrderOrSelection() throws {
        let first = text(frame: CGRect(x: 100, y: 200, width: 100, height: 20))
        let second = text(frame: CGRect(x: 205, y: 200, width: 20, height: 20))
        let point = CGPoint(x: 198, y: 210)
        XCTAssertTrue(first.frame.contains(point))
        XCTAssertFalse(second.frame.contains(point))
        XCTAssertTrue(LeadSheetCueTextEditOverlayGeometry.editHitFrame(for: second).contains(point))
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            for cues in [[first, second], [second, first]] {
                for selected in [UUID?.none, second.id, first.id] {
                    let context = context(cues: cues, selected: selected, style: style)
                    let router = RenderedEditRouter(providers: [CueTextRenderedEditHitTargetProvider()])
                    XCTAssertEqual(router.tapTarget(at: point, in: context)?.objectID, .cueText(first.id))
                    XCTAssertEqual(LeadSheetCueTextEditOverlayGeometry.hitTarget(at: point,
                        in: cues, selectedCueTextID: selected)?.cueTextID, first.id)
                    XCTAssertEqual(LeadSheetCueTextEditOverlayGeometry.bodyHitTarget(at: point, in: cues)?.id, first.id)
                    if selected == first.id {
                        XCTAssertEqual(router.dragTarget(at: point, in: context)?.objectID, .cueText(first.id))
                    } else {
                        XCTAssertNil(router.dragTarget(at: point, in: context),
                            "The neighboring selected cue cannot move from padding over the actual glyph")
                    }
                }
            }
        }
    }

    func testNeighborGlyphInControlPaddingStaysSelectableButVisibleButtonKeepsItsAction() throws {
        let owner = text(frame: CGRect(x: 100, y: 200, width: 70, height: 24))
        let buttons = controls(LeadSheetCueTextEditOverlayGeometry.controlFrames(for: owner))
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            for button in buttons {
                // The upper padding is still a usable button target when clear,
                // and yields when a neighboring cue is actually painted there.
                let paddingPoint = CGPoint(x: button.frame.midX, y: button.frame.minY - 3)
                let neighbor = text(frame: CGRect(x: paddingPoint.x - 4, y: paddingPoint.y - 1, width: 8, height: 2))
                let router = RenderedEditRouter(providers: [CueTextRenderedEditHitTargetProvider()])
                let padded = context(cues: [owner, neighbor], selected: owner.id, style: style)
                XCTAssertEqual(router.tapTarget(at: paddingPoint, in: padded)?.objectID, .cueText(neighbor.id))
                XCTAssertEqual(router.tapTarget(at: paddingPoint, in: padded)?.action, .select)
                XCTAssertEqual(LeadSheetCueTextEditOverlayGeometry.hitTarget(at: paddingPoint,
                    in: [owner, neighbor], selectedCueTextID: owner.id)?.cueTextID, neighbor.id)

                // Explicit button artwork keeps its command if a cue's glyph
                // physically overlaps it; only its invisible padding yields.
                let visiblePoint = CGPoint(x: button.frame.midX, y: button.frame.midY)
                let covered = text(frame: CGRect(x: visiblePoint.x - 4, y: visiblePoint.y - 4, width: 8, height: 8))
                let explicit = context(cues: [owner, covered], selected: owner.id, style: style)
                XCTAssertEqual(router.tapTarget(at: visiblePoint, in: explicit)?.objectID, .cueText(owner.id))
                XCTAssertEqual(router.tapTarget(at: visiblePoint, in: explicit)?.action, button.action)
                XCTAssertEqual(action(LeadSheetCueTextEditOverlayGeometry.hitTarget(at: visiblePoint,
                    in: [owner, covered], selectedCueTextID: owner.id)?.action), button.action)
            }
        }
    }

    func testOverlappingActualGlyphsDoNotCreateASelectionDeadSpot() {
        let first = text(frame: CGRect(x: 100, y: 200, width: 100, height: 20))
        let second = text(frame: CGRect(x: 180, y: 200, width: 40, height: 20))
        let point = CGPoint(x: 190, y: 210)
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            let router = RenderedEditRouter(providers: [CueTextRenderedEditHitTargetProvider()])
            XCTAssertEqual(router.tapTarget(at: point,
                in: context(cues: [first, second], selected: nil, style: style))?.objectID, .cueText(second.id))
        }
    }

    func testDistantCueRowsDoNotAccumulateCollisionExclusions() {
        let cues = (0..<500).map { index in
            text(frame: CGRect(x: 100, y: 200 + CGFloat(index) * 120, width: 70, height: 24))
        }
        let targets = CueTextRenderedEditHitTargetProvider().hitTargets(
            in: context(cues: cues, selected: cues[0].id, style: .rhythmSectionSheet))
        XCTAssertLessThanOrEqual(targets.reduce(0) { $0 + $1.excludedFrames.count }, 4,
            "Distant rows must not be copied into every cue's collision exclusions")
    }

    private func controls(_ frames: LeadSheetCueTextEditControlFrames) -> [(frame: CGRect, action: RenderedEditAction)] {
        [(frames.edit, .editText), (frames.shrink, .shrink), (frames.grow, .grow), (frames.delete, .delete)]
    }

    private func text(frame: CGRect) -> LeadSheetCueTextLayout {
        LeadSheetCueTextLayout(id: UUID(), text: "Cue", frame: frame,
            hitFrame: frame.insetBy(dx: -8, dy: -6), position: .above, emphasis: .normal,
            scale: 1, beatFraction: 0.5, verticalOffset: 0)
    }

    private func context(cues: [LeadSheetCueTextLayout], selected: UUID?, style: ChartLayoutStyle) -> RenderedEditContext {
        let chart = Chart.blank(title: "Text hit routing", measureCount: 1, layoutStyle: style)
        var page = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
        page.systems[0].measures[0].cueTextLayouts = cues
        var selection = RenderedEditSelectionState()
        if let selected { selection.select(.cueText(selected)) }
        return RenderedEditContext(pageLayout: page, layoutStyle: style, selection: selection)
    }

    private func action(_ legacy: CueTextEditHitTarget.Action?) -> RenderedEditAction? {
        switch legacy {
        case .select?: return .select
        case .edit?: return .editText
        case .shrink?: return .shrink
        case .grow?: return .grow
        case .delete?: return .delete
        case nil: return nil
        }
    }
}
#endif

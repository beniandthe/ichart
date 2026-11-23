#if canImport(UIKit)
import CoreText
import UIKit
import XCTest
@testable import iChart

@MainActor
final class CueTextContentBoundsTests: XCTestCase {
    func testShortAndMultilineCuesUseTightMeasuredTypographyInBothStylesAndFonts() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for family in [ChartFontFamilyPreset.finaleBroadway, .petaluma] {
                var chart = Chart.blank(title: "Measured cues", measureCount: 1, layoutStyle: style)
                chart.setMatchedFontFamily(family)
                let renderer = LeadSheetNotationRenderer(chart: chart)
                for scale in [0.75, 1.0, 1.8] {
                    for text in ["I", "Horns\nenter softly", "Horns\n\nenter softly"] {
                        let cue = model(text: text, scale: scale)
                        let metrics = renderer.cueTextRenderMetrics(for: cue, maximumWidth: 500)
                        let typesetter = LeadSheetCueTextTypesetter(text: text,
                            font: renderer.cueTextFont(emphasis: cue.emphasis, scale: CGFloat(scale)))
                        let drawing = typesetter.layout(width: metrics.size.width)
                        XCTAssertEqual(CTFrameGetVisibleStringRange(drawing.frame).length, (text as NSString).length)
                        XCTAssertEqual(metrics.lineCount, text.split(separator: "\n", omittingEmptySubsequences: false).count)
                        assertTight(metrics.size, around: drawing.frame, shiftedBy: drawing.baselineShift)
                        if text == "I" {
                            XCTAssertLessThan(metrics.size.width, 28, "A single narrow letter must not inherit a control-sized text rectangle")
                        }
                    }
                }
            }
        }
    }

    func testWrappedCueUsesItsWidestCompleteLineWithoutAnExtraMeasureWidthBox() throws {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        let text = "First time softly, then build into the final chorus"
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let renderer = LeadSheetNotationRenderer(chart: .blank(title: "Wrapped cue", measureCount: 1, layoutStyle: style))
            let cue = model(text: text)
            for width: CGFloat in [64, 90, 137] {
                let metrics = renderer.cueTextRenderMetrics(for: cue, maximumWidth: width)
                XCTAssertGreaterThan(metrics.lineCount, 1)
                XCTAssertLessThanOrEqual(metrics.size.width, width)
                let typesetter = LeadSheetCueTextTypesetter(text: text,
                    font: renderer.cueTextFont(emphasis: cue.emphasis, scale: 1))
                let drawing = typesetter.layout(width: metrics.size.width)
                XCTAssertEqual(CTFrameGetVisibleStringRange(drawing.frame).length, (text as NSString).length,
                    "A fitted wrapped box must retain the complete ending")
                assertTight(metrics.size, around: drawing.frame, shiftedBy: drawing.baselineShift)
            }
        }
    }

    func testVisibleSelectionFitsSmallTextWhileItsSeparateTouchTargetStaysComfortable() {
        let cue = layout(frame: CGRect(x: 150, y: 220, width: 4, height: 11))
        let visible = LeadSheetCueTextEditOverlayGeometry.editFrame(for: cue)
        XCTAssertEqual(visible, cue.frame.insetBy(dx: -2, dy: -2))
        XCTAssertEqual(visible.width, 8)
        XCTAssertEqual(visible.height, 15)
        let hit = LeadSheetCueTextEditOverlayGeometry.editHitFrame(for: cue)
        XCTAssertGreaterThanOrEqual(hit.width, 44)
        XCTAssertGreaterThanOrEqual(hit.height, 44)
        XCTAssertEqual(hit.midX, visible.midX)
        XCTAssertEqual(hit.midY, visible.midY)
        XCTAssertTrue(hit.contains(visible))
    }

    func testTopEdgeCueControlsMoveBelowTheTextAndKeepTheirRenderedAndHitRoutesAligned() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let chart = Chart.blank(title: "Top cue controls", measureCount: 1, layoutStyle: style)
            var page = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1400))
            let paper = page.pages[0].frame
            let cue = layout(frame: CGRect(x: paper.maxX - 12, y: paper.minY + 4, width: 5, height: 12))
            page.systems[0].measures[0].cueTextLayouts = [cue]
            var selection = RenderedEditSelectionState()
            selection.select(.cueText(cue.id))
            let context = RenderedEditContext(pageLayout: page, layoutStyle: style, selection: selection)
            let router = RenderedEditRouter(providers: [CueTextRenderedEditHitTargetProvider()])
            let controls = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cue, within: paper)
            let hits = LeadSheetCueTextEditOverlayGeometry.controlHitFrames(for: cue, within: paper)
            for (visible, hit, action) in [
                (controls.edit, hits.edit, RenderedEditAction.editText),
                (controls.shrink, hits.shrink, .shrink),
                (controls.grow, hits.grow, .grow),
                (controls.delete, hits.delete, .delete)
            ] {
                XCTAssertGreaterThan(visible.minY, cue.frame.maxY)
                XCTAssertTrue(paper.contains(hit), "Controls and their forgiving tap bounds must remain on the owning paper")
                XCTAssertFalse(hit.intersects(cue.frame))
                let point = CGPoint(x: visible.midX, y: visible.midY)
                XCTAssertEqual(router.tapTarget(at: point, in: context)?.action, action)
                XCTAssertNil(router.dragTarget(at: point, in: context))
                let legacy = LeadSheetCueTextEditOverlayGeometry.hitTarget(at: point, in: [cue],
                    selectedCueTextID: cue.id, controlBounds: paper)
                XCTAssertEqual(legacy?.cueTextID, cue.id)
            }
        }
    }

    private func assertTight(_ size: CGSize, around frame: CTFrame, shiftedBy shift: CGFloat,
        file: StaticString = #filePath, line: UInt = #line) {
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = Array(repeating: CGPoint.zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        var bounds = CGRect.null
        var widest: CGFloat = 0
        for (textLine, origin) in zip(lines, origins) {
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(textLine, &ascent, &descent, nil)
                - CTLineGetTrailingWhitespaceWidth(textLine))
            widest = max(widest, width)
            bounds = bounds.union(CGRect(x: origin.x, y: origin.y + shift - descent,
                width: max(0.01, width), height: ascent + descent))
        }
        XCTAssertGreaterThanOrEqual(size.width + 0.01, widest, file: file, line: line)
        XCTAssertLessThanOrEqual(size.width - widest, 2.01, "Only drawing safety space belongs in the measured width", file: file, line: line)
        XCTAssertGreaterThanOrEqual(bounds.minY, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(bounds.maxY, size.height, file: file, line: line)
        XCTAssertLessThanOrEqual(size.height - bounds.height, 2.01,
            "Text should have only drawing clearance (top \(size.height - bounds.maxY), bottom \(bounds.minY))",
            file: file, line: line)
    }

    private func model(text: String, scale: Double = 1) -> CueText {
        CueText(id: UUID(), text: text, anchorMeasureID: UUID(), position: .below,
            emphasis: .normal, scale: scale)
    }

    private func layout(frame: CGRect) -> LeadSheetCueTextLayout {
        LeadSheetCueTextLayout(id: UUID(), text: "I", frame: frame,
            hitFrame: frame.insetBy(dx: -6, dy: -5), position: .above, emphasis: .normal,
            scale: 1, beatFraction: nil, verticalOffset: 0)
    }
}
#endif

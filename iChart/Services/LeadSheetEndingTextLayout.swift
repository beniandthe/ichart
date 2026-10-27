import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#endif

struct LeadSheetEndingLabelMetrics {
    var fontSize: CGFloat
    var lineCount: Int
    var height: CGFloat
    var bandHeight: CGFloat
}

enum LeadSheetEndingTextLayout {
    static func metrics(text: String, width: CGFloat, chart: Chart) -> LeadSheetEndingLabelMetrics {
        let fontSize: CGFloat = (chart.layoutStyle == .rhythmSectionSheet ? 12.4 : 12)
            * chart.notationReadability.navigationScale
        let resolvedWidth = max(1, width)
        let lineCount: Int
        let height: CGFloat
        #if canImport(UIKit)
        let attributed = LeadSheetNotationRenderer(chart: chart).endingLabelAttributedText(text, fontSize: fontSize)
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: resolvedWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let range = manager.glyphRange(for: container)
        var measuredLines = 0
        manager.enumerateLineFragments(forGlyphRange: range) { _, _, _, _, _ in
            measuredLines += 1
        }
        lineCount = max(1, measuredLines)
        height = ceil(manager.usedRect(for: container).height)
        #else
        // The non-UIKit model/test target has no font engine. Keep a conservative
        // estimate there; iPad layout and PDF export share the actual font above.
        let charactersPerLine = max(1, Int(floor(resolvedWidth / max(1, fontSize * 0.62))))
        var measuredLines = 1
        var currentCount = 0
        for character in text {
            if character == "\n" {
                measuredLines += 1
                currentCount = 0
            } else {
                if currentCount >= charactersPerLine {
                    measuredLines += 1
                    currentCount = 0
                }
                currentCount += 1
            }
        }
        lineCount = measuredLines
        height = CGFloat(lineCount) * ceil(fontSize * 1.25)
        #endif
        let isLegacyCompactLabel = lineCount == 1 && (text == "1." || text == "2.")
        let bandHeight = isLegacyCompactLabel
            ? chart.notationReadability.endingHeight
            : max(chart.notationReadability.endingHeight, height + 5)
        return LeadSheetEndingLabelMetrics(fontSize: fontSize, lineCount: lineCount, height: height, bandHeight: bandHeight)
    }
}

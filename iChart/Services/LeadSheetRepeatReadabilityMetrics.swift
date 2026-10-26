import CoreGraphics

/// Shared dimensions for repeat rendering, layout clearance, and editor targeting.
struct LeadSheetRepeatReadabilityMetrics {
    let lineWidth: CGFloat
    let separation: CGFloat
    let dotRadius: CGFloat
    let dotOffset: CGFloat
    let wingLength: CGFloat
    let wingHeight: CGFloat
    let wingLineWidth: CGFloat

    init(chart: Chart, staffHeight: CGFloat) {
        let staffSpace = max(1, (staffHeight - 4) / 4)
        let emphasis = chart.notationReadability.strokeScale
        lineWidth = LeadSheetBarlineMetrics.repeatLineWidth(
            staffSpace: staffSpace,
            strokeScale: chart.engravingPreset.strokeScale,
            layoutStyle: chart.layoutStyle
        ) * emphasis
        let baseSeparation = LeadSheetBarlineMetrics.repeatSeparation(
            staffSpace: staffSpace,
            layoutStyle: chart.layoutStyle
        )
        separation = chart.notationReadability == .performance
            ? max(baseSeparation, lineWidth * 1.9)
            : baseSeparation
        dotRadius = LeadSheetBarlineMetrics.repeatDotRadius(
            staffSpace: staffSpace,
            layoutStyle: chart.layoutStyle
        ) * (chart.notationReadability == .performance ? 1.35 : 1)
        dotOffset = LeadSheetBarlineMetrics.repeatDotOffset(
            thinLineWidth: lineWidth,
            dotRadius: dotRadius,
            staffSpace: staffSpace,
            layoutStyle: chart.layoutStyle
        )
        wingLength = chart.repeatWings ? max(5, staffSpace * 0.65) : 0
        wingHeight = chart.repeatWings ? max(3.5, staffSpace * 0.38) : 0
        wingLineWidth = max(1.25, lineWidth * 0.78)
    }

    var horizontalExtent: CGFloat {
        let dotExtent = separation / 2 + dotOffset + dotRadius
        let wingExtent = separation / 2 + wingLength + wingLineWidth / 2
        return max(dotExtent, wingExtent, separation / 2 + lineWidth / 2)
    }

    var verticalOutset: CGFloat {
        wingHeight > 0 ? wingHeight + wingLineWidth / 2 : 0
    }
}

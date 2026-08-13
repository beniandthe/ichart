#if canImport(UIKit)
import PencilKit
import UIKit

struct LeadSheetInkTelemetrySnapshot {
    var strokeCount: Int
    var pointCount: Int
    var lightStrokeCount: Int
    var minOpacity: Double
    var medianOpacity: Double
    var maxOpacity: Double
    var minWidth: Double
    var medianWidth: Double
    var maxWidth: Double
    var hasMask: Bool
    var normalizationNeeded: Bool

    static func capture(drawing: PKDrawing) -> LeadSheetInkTelemetrySnapshot {
        var opacities: [Double] = []
        var widths: [Double] = []
        var pointCount = 0
        var lightStrokeCount = 0
        var hasMask = false

        for stroke in drawing.strokes {
            if inkIsLight(stroke.ink) {
                lightStrokeCount += 1
            }
            if stroke.mask != nil {
                hasMask = true
            }

            for point in stroke.path {
                pointCount += 1
                opacities.append(Double(point.opacity))
                widths.append(Double(max(point.size.width, point.size.height)))
            }
        }

        return LeadSheetInkTelemetrySnapshot(
            strokeCount: drawing.strokes.count,
            pointCount: pointCount,
            lightStrokeCount: lightStrokeCount,
            minOpacity: opacities.min() ?? 0,
            medianOpacity: median(opacities),
            maxOpacity: opacities.max() ?? 0,
            minWidth: widths.min() ?? 0,
            medianWidth: median(widths),
            maxWidth: widths.max() ?? 0,
            hasMask: hasMask,
            normalizationNeeded: LeadSheetPersistentInkColorPolicy.needsNormalization(drawing)
        )
    }

    func telemetryProperties(scope: LeadSheetActiveInkScope, normalizedBeforeSave: Bool) -> IChartTelemetryProperties {
        [
            "scope": .string(scope.telemetryValue),
            "stroke_count": .int(strokeCount),
            "point_count": .int(pointCount),
            "light_stroke_count": .int(lightStrokeCount),
            "min_opacity": .double(minOpacity),
            "median_opacity": .double(medianOpacity),
            "max_opacity": .double(maxOpacity),
            "min_width": .double(minWidth),
            "median_width": .double(medianWidth),
            "max_width": .double(maxWidth),
            "has_mask": .bool(hasMask),
            "normalization_needed": .bool(normalizationNeeded),
            "normalized_before_save": .bool(normalizedBeforeSave)
        ]
    }

    private static func inkIsLight(_ ink: PKInk) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }

        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return alpha > 0.05 && luminance >= 0.86
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let sortedValues = values.sorted()
        let middleIndex = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2
        }

        return sortedValues[middleIndex]
    }
}
#endif

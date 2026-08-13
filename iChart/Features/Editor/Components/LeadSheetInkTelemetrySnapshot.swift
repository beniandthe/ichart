#if canImport(UIKit)
import PencilKit
import UIKit

struct LeadSheetInkTelemetrySnapshot {
    var strokeCount: Int
    var pointCount: Int
    var lightStrokeCount: Int
    var strokeColorMinLuminance: Double
    var strokeColorMedianLuminance: Double
    var strokeColorMaxLuminance: Double
    var minOpacity: Double
    var medianOpacity: Double
    var maxOpacity: Double
    var minWidth: Double
    var medianWidth: Double
    var maxWidth: Double
    var hasMask: Bool
    var normalizationNeeded: Bool
    var toolInkType: String
    var toolColorLuminance: Double
    var canvasUserInterfaceStyle: String
    var canvasBackgroundAlpha: Double
    var canvasIsOpaque: Bool
    var renderedInkMedianLuminance: Double
    var renderedInkLightPixelRatio: Double
    var renderedInkSampleCount: Int

    static func capture(
        drawing: PKDrawing,
        canvasView: PKCanvasView? = nil
    ) -> LeadSheetInkTelemetrySnapshot {
        var opacities: [Double] = []
        var widths: [Double] = []
        var strokeColorLuminances: [Double] = []
        var pointCount = 0
        var lightStrokeCount = 0
        var hasMask = false

        for stroke in drawing.strokes {
            if let strokeLuminance = colorLuminance(stroke.ink.color) {
                strokeColorLuminances.append(strokeLuminance)
            }
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

        let toolDiagnostics = toolDiagnostics(for: canvasView)
        let canvasDiagnostics = canvasDiagnostics(for: canvasView)
        let renderedDiagnostics = renderedInkDiagnostics(for: drawing)

        return LeadSheetInkTelemetrySnapshot(
            strokeCount: drawing.strokes.count,
            pointCount: pointCount,
            lightStrokeCount: lightStrokeCount,
            strokeColorMinLuminance: strokeColorLuminances.min() ?? -1,
            strokeColorMedianLuminance: median(strokeColorLuminances, emptyValue: -1),
            strokeColorMaxLuminance: strokeColorLuminances.max() ?? -1,
            minOpacity: opacities.min() ?? 0,
            medianOpacity: median(opacities),
            maxOpacity: opacities.max() ?? 0,
            minWidth: widths.min() ?? 0,
            medianWidth: median(widths),
            maxWidth: widths.max() ?? 0,
            hasMask: hasMask,
            normalizationNeeded: LeadSheetPersistentInkColorPolicy.needsNormalization(drawing),
            toolInkType: toolDiagnostics.inkType,
            toolColorLuminance: toolDiagnostics.colorLuminance,
            canvasUserInterfaceStyle: canvasDiagnostics.userInterfaceStyle,
            canvasBackgroundAlpha: canvasDiagnostics.backgroundAlpha,
            canvasIsOpaque: canvasDiagnostics.isOpaque,
            renderedInkMedianLuminance: renderedDiagnostics.medianLuminance,
            renderedInkLightPixelRatio: renderedDiagnostics.lightPixelRatio,
            renderedInkSampleCount: renderedDiagnostics.sampleCount
        )
    }

    func telemetryProperties(scope: LeadSheetActiveInkScope, normalizedBeforeSave: Bool) -> IChartTelemetryProperties {
        [
            "scope": .string(scope.telemetryValue),
            "stroke_count": .int(strokeCount),
            "point_count": .int(pointCount),
            "light_stroke_count": .int(lightStrokeCount),
            "stroke_color_min_luminance": .double(strokeColorMinLuminance),
            "stroke_color_median_luminance": .double(strokeColorMedianLuminance),
            "stroke_color_max_luminance": .double(strokeColorMaxLuminance),
            "min_opacity": .double(minOpacity),
            "median_opacity": .double(medianOpacity),
            "max_opacity": .double(maxOpacity),
            "min_width": .double(minWidth),
            "median_width": .double(medianWidth),
            "max_width": .double(maxWidth),
            "has_mask": .bool(hasMask),
            "normalization_needed": .bool(normalizationNeeded),
            "normalized_before_save": .bool(normalizedBeforeSave),
            "tool_ink_type": .string(toolInkType),
            "tool_color_luminance": .double(toolColorLuminance),
            "canvas_user_interface_style": .string(canvasUserInterfaceStyle),
            "canvas_background_alpha": .double(canvasBackgroundAlpha),
            "canvas_is_opaque": .bool(canvasIsOpaque),
            "rendered_ink_median_luminance": .double(renderedInkMedianLuminance),
            "rendered_ink_light_pixel_ratio": .double(renderedInkLightPixelRatio),
            "rendered_ink_sample_count": .int(renderedInkSampleCount)
        ]
    }

    private static func inkIsLight(_ ink: PKInk) -> Bool {
        guard let luminance = colorLuminance(ink.color),
              let alpha = colorAlpha(ink.color) else {
            return false
        }

        return alpha > 0.05 && luminance >= 0.86
    }

    private static func colorLuminance(_ color: UIColor) -> Double? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return Double(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    }

    private static func colorAlpha(_ color: UIColor) -> Double? {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }

        return Double(alpha)
    }

    private static func toolDiagnostics(for canvasView: PKCanvasView?) -> (
        inkType: String,
        colorLuminance: Double
    ) {
        guard let tool = canvasView?.tool as? PKInkingTool else {
            return ("non_inking", -1)
        }

        return (
            String(describing: tool.inkType),
            colorLuminance(tool.color) ?? -1
        )
    }

    private static func canvasDiagnostics(for canvasView: PKCanvasView?) -> (
        userInterfaceStyle: String,
        backgroundAlpha: Double,
        isOpaque: Bool
    ) {
        guard let canvasView else {
            return ("unknown", -1, false)
        }

        return (
            userInterfaceStyleDescription(canvasView.traitCollection.userInterfaceStyle),
            colorAlpha(canvasView.backgroundColor ?? .clear) ?? -1,
            canvasView.isOpaque
        )
    }

    private static func userInterfaceStyleDescription(_ style: UIUserInterfaceStyle) -> String {
        switch style {
        case .light:
            return "light"
        case .dark:
            return "dark"
        case .unspecified:
            return "unspecified"
        @unknown default:
            return "unknown"
        }
    }

    private static func renderedInkDiagnostics(for drawing: PKDrawing) -> (
        medianLuminance: Double,
        lightPixelRatio: Double,
        sampleCount: Int
    ) {
        let renderBounds = drawing.strokes.reduce(CGRect.null) { partialBounds, stroke in
            let strokeBounds = stroke.renderBounds
            guard !strokeBounds.isNull else {
                return partialBounds
            }

            return partialBounds.isNull ? strokeBounds : partialBounds.union(strokeBounds)
        }

        guard !renderBounds.isNull,
              renderBounds.width > 0,
              renderBounds.height > 0 else {
            return (-1, 0, 0)
        }

        let paddedBounds = renderBounds.insetBy(dx: -2, dy: -2)
        guard let cgImage = drawing.image(from: paddedBounds, scale: 1).cgImage else {
            return (-1, 0, 0)
        }

        let width = min(64, max(1, cgImage.width))
        let height = min(64, max(1, cgImage.height))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let baseAddress = rawBuffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.interpolationQuality = .low
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard didDraw else {
            return (-1, 0, 0)
        }

        var luminances: [Double] = []
        var lightPixelCount = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255.0
            guard alpha > 0.05 else {
                continue
            }

            let red = min(1, Double(pixels[index]) / 255.0 / alpha)
            let green = min(1, Double(pixels[index + 1]) / 255.0 / alpha)
            let blue = min(1, Double(pixels[index + 2]) / 255.0 / alpha)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            luminances.append(luminance)
            if luminance >= 0.86 {
                lightPixelCount += 1
            }
        }

        guard !luminances.isEmpty else {
            return (-1, 0, 0)
        }

        return (
            median(luminances),
            Double(lightPixelCount) / Double(luminances.count),
            luminances.count
        )
    }

    private static func median(_ values: [Double], emptyValue: Double = 0) -> Double {
        guard !values.isEmpty else {
            return emptyValue
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

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
    var toolIsInking: Bool
    var toolMatchesPersistentInk: Bool
    var toolWidth: Double
    var canvasUserInterfaceStyle: String
    var canvasOverrideUserInterfaceStyle: String
    var canvasSuperviewUserInterfaceStyle: String
    var canvasWindowUserInterfaceStyle: String
    var canvasDrawingPolicy: String
    var canvasAlpha: Double
    var canvasBackgroundAlpha: Double
    var canvasIsOpaque: Bool
    var canvasIsHidden: Bool
    var canvasUserInteractionEnabled: Bool
    var canvasIsFirstResponder: Bool
    var canvasContentScale: Double
    var canvasBoundsWidth: Double
    var canvasBoundsHeight: Double
    var liveCanvasLightTraitGuardEnabled: Bool
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
            toolIsInking: toolDiagnostics.isInking,
            toolMatchesPersistentInk: toolDiagnostics.matchesPersistentInk,
            toolWidth: toolDiagnostics.width,
            canvasUserInterfaceStyle: canvasDiagnostics.userInterfaceStyle,
            canvasOverrideUserInterfaceStyle: canvasDiagnostics.overrideUserInterfaceStyle,
            canvasSuperviewUserInterfaceStyle: canvasDiagnostics.superviewUserInterfaceStyle,
            canvasWindowUserInterfaceStyle: canvasDiagnostics.windowUserInterfaceStyle,
            canvasDrawingPolicy: canvasDiagnostics.drawingPolicy,
            canvasAlpha: canvasDiagnostics.alpha,
            canvasBackgroundAlpha: canvasDiagnostics.backgroundAlpha,
            canvasIsOpaque: canvasDiagnostics.isOpaque,
            canvasIsHidden: canvasDiagnostics.isHidden,
            canvasUserInteractionEnabled: canvasDiagnostics.userInteractionEnabled,
            canvasIsFirstResponder: canvasDiagnostics.isFirstResponder,
            canvasContentScale: canvasDiagnostics.contentScale,
            canvasBoundsWidth: canvasDiagnostics.boundsWidth,
            canvasBoundsHeight: canvasDiagnostics.boundsHeight,
            liveCanvasLightTraitGuardEnabled: canvasDiagnostics.liveLightTraitGuardEnabled,
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
            "tool_is_inking": .bool(toolIsInking),
            "tool_matches_persistent_ink": .bool(toolMatchesPersistentInk),
            "tool_width": .double(toolWidth),
            "canvas_user_interface_style": .string(canvasUserInterfaceStyle),
            "canvas_override_user_interface_style": .string(canvasOverrideUserInterfaceStyle),
            "canvas_superview_user_interface_style": .string(canvasSuperviewUserInterfaceStyle),
            "canvas_window_user_interface_style": .string(canvasWindowUserInterfaceStyle),
            "canvas_drawing_policy": .string(canvasDrawingPolicy),
            "canvas_alpha": .double(canvasAlpha),
            "canvas_background_alpha": .double(canvasBackgroundAlpha),
            "canvas_is_opaque": .bool(canvasIsOpaque),
            "canvas_is_hidden": .bool(canvasIsHidden),
            "canvas_user_interaction_enabled": .bool(canvasUserInteractionEnabled),
            "canvas_is_first_responder": .bool(canvasIsFirstResponder),
            "canvas_content_scale": .double(canvasContentScale),
            "canvas_bounds_width": .double(canvasBoundsWidth),
            "canvas_bounds_height": .double(canvasBoundsHeight),
            "live_canvas_light_trait_guard_enabled": .bool(liveCanvasLightTraitGuardEnabled),
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

    private struct ToolDiagnostics {
        var inkType: String
        var colorLuminance: Double
        var isInking: Bool
        var matchesPersistentInk: Bool
        var width: Double
    }

    private struct CanvasDiagnostics {
        var userInterfaceStyle: String
        var overrideUserInterfaceStyle: String
        var superviewUserInterfaceStyle: String
        var windowUserInterfaceStyle: String
        var drawingPolicy: String
        var alpha: Double
        var backgroundAlpha: Double
        var isOpaque: Bool
        var isHidden: Bool
        var userInteractionEnabled: Bool
        var isFirstResponder: Bool
        var contentScale: Double
        var boundsWidth: Double
        var boundsHeight: Double
        var liveLightTraitGuardEnabled: Bool
    }

    private static func toolDiagnostics(for canvasView: PKCanvasView?) -> ToolDiagnostics {
        guard let tool = canvasView?.tool as? PKInkingTool else {
            return ToolDiagnostics(
                inkType: "non_inking",
                colorLuminance: -1,
                isInking: false,
                matchesPersistentInk: false,
                width: -1
            )
        }

        return ToolDiagnostics(
            inkType: String(describing: tool.inkType),
            colorLuminance: colorLuminance(tool.color) ?? -1,
            isInking: true,
            matchesPersistentInk: LeadSheetPersistentInkColorPolicy.matchesPersistentInkColor(tool.color),
            width: Double(tool.width)
        )
    }

    private static func canvasDiagnostics(for canvasView: PKCanvasView?) -> CanvasDiagnostics {
        guard let canvasView else {
            return CanvasDiagnostics(
                userInterfaceStyle: "unknown",
                overrideUserInterfaceStyle: "unknown",
                superviewUserInterfaceStyle: "unknown",
                windowUserInterfaceStyle: "unknown",
                drawingPolicy: "unknown",
                alpha: -1,
                backgroundAlpha: -1,
                isOpaque: false,
                isHidden: false,
                userInteractionEnabled: false,
                isFirstResponder: false,
                contentScale: -1,
                boundsWidth: -1,
                boundsHeight: -1,
                liveLightTraitGuardEnabled: false
            )
        }

        let effectiveStyle = canvasView.traitCollection.userInterfaceStyle
        let overrideStyle = canvasView.overrideUserInterfaceStyle

        return CanvasDiagnostics(
            userInterfaceStyle: userInterfaceStyleDescription(effectiveStyle),
            overrideUserInterfaceStyle: userInterfaceStyleDescription(overrideStyle),
            superviewUserInterfaceStyle: canvasView.superview.map {
                userInterfaceStyleDescription($0.traitCollection.userInterfaceStyle)
            } ?? "unknown",
            windowUserInterfaceStyle: canvasView.window.map {
                userInterfaceStyleDescription($0.traitCollection.userInterfaceStyle)
            } ?? "unknown",
            drawingPolicy: drawingPolicyDescription(canvasView.drawingPolicy),
            alpha: Double(canvasView.alpha),
            backgroundAlpha: colorAlpha(canvasView.backgroundColor ?? .clear) ?? -1,
            isOpaque: canvasView.isOpaque,
            isHidden: canvasView.isHidden,
            userInteractionEnabled: canvasView.isUserInteractionEnabled,
            isFirstResponder: canvasView.isFirstResponder,
            contentScale: Double(canvasView.contentScaleFactor),
            boundsWidth: Double(canvasView.bounds.width),
            boundsHeight: Double(canvasView.bounds.height),
            liveLightTraitGuardEnabled: overrideStyle == .light && effectiveStyle == .light
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

    private static func drawingPolicyDescription(_ policy: PKCanvasViewDrawingPolicy) -> String {
        switch policy {
        case .default:
            return "default"
        case .anyInput:
            return "any_input"
        case .pencilOnly:
            return "pencil_only"
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
        guard let drawingData = LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing),
              let cgImage = LeadSheetSavedInkRenderer.renderedInkImage(
                drawingData,
                in: paddedBounds,
                scale: 1
              )?.cgImage else {
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

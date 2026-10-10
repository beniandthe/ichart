import CoreGraphics
import Foundation

enum ChordInkRasterizer {
    static func rasterize(
        _ packet: ChordInkCanonicalTrajectoryPacket
    ) throws -> ChordInkRasterFeaturePlane {
        try rasterize(prepared: ChordInkPreparedFeatureGeometry.prepare(packet: packet))
    }

    static func rasterize(
        strokes: [InkStroke]
    ) throws -> ChordInkRasterFeaturePlane {
        try rasterize(prepared: ChordInkPreparedFeatureGeometry.prepare(strokes: strokes))
    }

    private static func rasterize(
        prepared: ChordInkPreparedFeatureGeometry
    ) throws -> ChordInkRasterFeaturePlane {
        let width = ChordInkFeatureSchema.rasterWidth
        let height = ChordInkFeatureSchema.rasterHeight
        var pixels = Array(
            repeating: ChordInkFeatureSchema.rasterBackground,
            count: width * height
        )
        let radius = ChordInkFeatureSchema.rasterStrokeWidth / 2
        let horizontalSpan = Double(width)
            - 2 * (ChordInkFeatureSchema.rasterPadding + radius)
        let verticalSpan = Double(height)
            - 2 * (ChordInkFeatureSchema.rasterPadding + radius)
        let horizontalScale = prepared.normalizedWidth > 0
            ? horizontalSpan / prepared.normalizedWidth
            : Double.infinity
        let verticalScale = prepared.normalizedHeight > 0
            ? verticalSpan / prepared.normalizedHeight
            : Double.infinity
        let finiteScales = [horizontalScale, verticalScale].filter(\.isFinite)
        let scale = finiteScales.min() ?? 0
        let centerX = Double(width) / 2
        let centerY = Double(height) / 2

        func mapped(_ point: ChordInkPreparedFeatureGeometry.Point) -> CGPoint {
            CGPoint(
                x: centerX + point.x * scale,
                y: centerY + point.y * scale
            )
        }

        for stroke in prepared.strokes {
            if stroke.points.count == 1 {
                drawRoundSegment(
                    from: mapped(stroke.points[0]),
                    to: mapped(stroke.points[0]),
                    radius: radius,
                    width: width,
                    height: height,
                    pixels: &pixels
                )
                continue
            }
            for index in stroke.points.indices.dropFirst() {
                drawRoundSegment(
                    from: mapped(stroke.points[index - 1]),
                    to: mapped(stroke.points[index]),
                    radius: radius,
                    width: width,
                    height: height,
                    pixels: &pixels
                )
            }
        }
        return ChordInkRasterFeaturePlane(pixels: pixels)
    }

    private static func drawRoundSegment(
        from start: CGPoint,
        to end: CGPoint,
        radius: Double,
        width: Int,
        height: Int,
        pixels: inout [UInt8]
    ) {
        let minPixelX = max(0, Int(floor(min(start.x, end.x) - radius - 0.5)))
        let maxPixelX = min(width - 1, Int(ceil(max(start.x, end.x) + radius - 0.5)))
        let minPixelY = max(0, Int(floor(min(start.y, end.y) - radius - 0.5)))
        let maxPixelY = min(height - 1, Int(ceil(max(start.y, end.y) + radius - 0.5)))
        guard minPixelX <= maxPixelX, minPixelY <= maxPixelY else { return }

        let dx = Double(end.x - start.x)
        let dy = Double(end.y - start.y)
        let squaredLength = dx * dx + dy * dy
        let squaredRadius = radius * radius

        for y in minPixelY...maxPixelY {
            for x in minPixelX...maxPixelX {
                let pixelX = Double(x) + 0.5
                let pixelY = Double(y) + 0.5
                let fraction: Double
                if squaredLength > 0 {
                    fraction = min(
                        1,
                        max(
                            0,
                            ((pixelX - Double(start.x)) * dx
                                + (pixelY - Double(start.y)) * dy) / squaredLength
                        )
                    )
                } else {
                    fraction = 0
                }
                let closestX = Double(start.x) + fraction * dx
                let closestY = Double(start.y) + fraction * dy
                let distanceX = pixelX - closestX
                let distanceY = pixelY - closestY
                if distanceX * distanceX + distanceY * distanceY <= squaredRadius {
                    pixels[y * width + x] = ChordInkFeatureSchema.rasterForeground
                }
            }
        }
    }
}

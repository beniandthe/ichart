import CoreGraphics
import Foundation

enum FreehandSymbolLane: String, Codable, CaseIterable, Hashable {
    case chartArea
    case aboveMeasure
    case belowMeasure
}

struct FreehandSymbolMeasureFrame: Codable, Hashable {
    var offsetX: Double
    var offsetY: Double
    var width: Double
    var height: Double

    init(offsetX: Double, offsetY: Double, width: Double, height: Double) {
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.width = max(0, width)
        self.height = max(0, height)
    }

    init(frame: CGRect, relativeTo measureFrame: CGRect) {
        self.init(
            offsetX: Double(frame.minX - measureFrame.minX),
            offsetY: Double(frame.minY - measureFrame.minY),
            width: Double(frame.width),
            height: Double(frame.height)
        )
    }

    func resolved(relativeTo measureFrame: CGRect) -> CGRect {
        CGRect(
            x: measureFrame.minX + CGFloat(offsetX),
            y: measureFrame.minY + CGFloat(offsetY),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

struct FreehandSymbolNormalizedFrame: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = max(0, width)
        self.height = max(0, height)
    }

    init(frame: CGRect, in laneFrame: CGRect) {
        guard laneFrame.width > 0,
              laneFrame.height > 0 else {
            self.init(x: 0, y: 0, width: 0, height: 0)
            return
        }

        self.init(
            x: Double((frame.minX - laneFrame.minX) / laneFrame.width),
            y: Double((frame.minY - laneFrame.minY) / laneFrame.height),
            width: Double(frame.width / laneFrame.width),
            height: Double(frame.height / laneFrame.height)
        )
    }

    func resolved(in laneFrame: CGRect) -> CGRect {
        CGRect(
            x: laneFrame.minX + CGFloat(x) * laneFrame.width,
            y: laneFrame.minY + CGFloat(y) * laneFrame.height,
            width: CGFloat(width) * laneFrame.width,
            height: CGFloat(height) * laneFrame.height
        )
    }
}

struct FreehandSymbol: Identifiable, Codable, Hashable {
    var id: UUID
    var anchorMeasureID: UUID
    var lane: FreehandSymbolLane
    var normalizedFrame: FreehandSymbolNormalizedFrame
    var measureRelativeFrame: FreehandSymbolMeasureFrame? = nil
    var drawingData: Data
    var zIndex: Int
}

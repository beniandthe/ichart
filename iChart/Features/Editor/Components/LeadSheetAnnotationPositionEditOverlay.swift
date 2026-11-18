#if canImport(UIKit)
import UIKit

/// The placement control uses the same paper geometry for touch routing and
/// display. It keeps range and text controls usable when annotations stack.
enum LeadSheetAnnotationPositionEditOverlay {
    struct Handle {
        let frame: CGRect
        let annotationFrame: CGRect
        let offsetFromDefault: CGFloat
    }

    static func handles(for context: RenderedEditContext) -> [Handle] {
        let pageLayout = context.pageLayout
        let scale = max(0.1, context.screenPointsPerDisplayedPoint)
        let touchHeight = LeadSheetEndingEditOverlay.minimumScreenTouchSize / scale
        let obstacles = LeadSheetEndingOverlayPlacement.notationObstacles(in: pageLayout, scale: scale)
        var reserved: [CGRect] = []
        let annotations: [(LeadSheetSystemLayout, CGRect, CGFloat)]
        switch context.selection.selectedObjectID {
        case .cueText(let id):
            annotations = pageLayout.systems.flatMap { system in
                system.measures.flatMap(\.cueTextLayouts).filter { $0.id == id }.map { cue in
                    let controls = LeadSheetCueTextEditOverlayGeometry.controlFrames(for: cue)
                    let outset = LeadSheetCueTextEditOverlayGeometry.controlHitOutset
                    reserved += [controls.edit, controls.shrink, controls.grow, controls.delete]
                        .map { $0.insetBy(dx: -outset, dy: -outset) }
                    return (system, cue.frame, cue.verticalOffsetFromDefault)
                }
            }
        case .roadmapMarker(let id):
            annotations = pageLayout.systems.flatMap { system in
                system.roadmapMarkerLayouts.filter { $0.id == id }.map { marker in
                    let delete = LeadSheetRoadmapMarkerEditOverlayGeometry.controlFrames(for: marker).delete
                    let outset = LeadSheetRoadmapMarkerEditOverlayGeometry.controlHitOutset
                    reserved.append(delete.insetBy(dx: -outset, dy: -outset))
                    let frame = marker.frame.union(LeadSheetRoadmapMarkerLabelGeometry.labelFrame(for: marker))
                    return (system, frame, marker.verticalOffsetFromDefault)
                }
            }
        case .endingSpan(let id):
            reserved = LeadSheetEndingEditOverlay.controlFrames(for: id, in: pageLayout,
                screenPointsPerDisplayedPoint: scale).flatMap { controls in
                    [controls.moveHandle] + (controls.lengthenHandle.map { [$0] } ?? [])
                }
            annotations = pageLayout.systems.flatMap { system in
                system.endingLayouts.filter { $0.roadmapObjectID == id }.map {
                    (system, $0.occupiedFrame, $0.verticalOffsetFromDefault)
                }
            }
        default:
            return []
        }
        return annotations.compactMap { system, annotationFrame, offsetFromDefault in
            let paper = pageLayout.paperFrame(for: system)
            let width = min(138 / scale, paper.width - 12 / scale)
            guard width >= touchHeight else { return nil }
            let preferred = CGPoint(x: annotationFrame.maxX + 8 / scale,
                y: annotationFrame.midY - touchHeight / 2)
            guard let frame = LeadSheetEndingOverlayPlacement.frame(
                size: CGSize(width: width, height: touchHeight), preferredOrigin: preferred,
                inside: paper, obstacles: obstacles, reserved: reserved, scale: scale
            ) else { return nil }
            reserved.append(frame)
            return Handle(frame: frame, annotationFrame: annotationFrame, offsetFromDefault: offsetFromDefault)
        }
    }
}

/// A visible grab target with an equivalent VoiceOver up/down action.
final class LeadSheetAnnotationPositionHandleView: UILabel {
    var adjustment: ((CGFloat) -> Void)?

    init() {
        super.init(frame: .zero)
        text = "Move Up or Down"
        textAlignment = .center
        textColor = .systemBlue
        backgroundColor = .systemBackground
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.75
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityIdentifier = "annotation.move-up-or-down"
        accessibilityLabel = text
        accessibilityHint = "Drag vertically to place this annotation."
        accessibilityTraits = .adjustable
        layer.borderColor = UIColor.systemBlue.cgColor
    }

    required init?(coder: NSCoder) { return nil }

    func updateFrame(_ frame: CGRect, scale: CGFloat, modelOffset: Double) {
        self.frame = frame
        font = .systemFont(ofSize: 13 / scale, weight: .semibold)
        layer.cornerRadius = 8 / scale
        layer.borderWidth = 1 / scale
        clipsToBounds = true
        accessibilityValue = modelOffset == 0 ? "Automatic placement" : "Custom placement"
    }

    override func accessibilityIncrement() { adjustment?(-8) }
    override func accessibilityDecrement() { adjustment?(8) }
}

/// Tracks a frozen source layout and chart value for one vertical gesture.
/// Only the visual offset can change when the gesture commits.
struct LeadSheetAnnotationPositionDrag {
    let objectID: RenderedEditObjectID
    let chartID: UUID
    let modelOffset: Double
    let startingOffsetFromDefault: CGFloat
    let startY: CGFloat
    let screenPointsPerDisplayedPoint: CGFloat

    static func modelOffset(for objectID: RenderedEditObjectID, in chart: Chart) -> Double? {
        switch objectID {
        case .cueText(let id):
            return chart.cueText(id: id)?.verticalOffset
        case .roadmapMarker(let id), .endingSpan(let id):
            return chart.roadmapObject(id: id)?.resolvedVerticalOffset
        default:
            return nil
        }
    }

    static func setOffset(_ offset: Double, for objectID: RenderedEditObjectID, in chart: inout Chart) -> Bool {
        switch objectID {
        case .cueText(let id):
            return chart.setCueTextVerticalOffset(id, to: offset)
        case .roadmapMarker(let id), .endingSpan(let id):
            return chart.setRoadmapAnnotationVerticalOffset(id, to: offset)
        default:
            return false
        }
    }

    func offset(at y: CGFloat) -> Double {
        CueText.clampedVerticalOffset(Double(startingOffsetFromDefault + y - startY))
    }

    func previewTranslation(at y: CGFloat) -> CGFloat {
        guard y != startY else { return 0 }
        return CGFloat(offset(at: y)) - startingOffsetFromDefault
    }

    func commit(in chart: inout Chart, selected: RenderedEditObjectID?, at y: CGFloat) -> Bool {
        guard y.isFinite, abs(y - startY) * screenPointsPerDisplayedPoint >= 2,
              chart.id == chartID, objectID == selected,
              Self.modelOffset(for: objectID, in: chart) == modelOffset else { return false }
        return Self.setOffset(offset(at: y), for: objectID, in: &chart)
    }
}
#endif

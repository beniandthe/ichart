#if canImport(UIKit)
import UIKit

struct LeadSheetCanvasTapAcknowledgementSnapshot: Equatable {
    let center: CGPoint
    let frame: CGRect
    let reducesMotion: Bool
    let sequence: UInt64
}

/// A short receipt for an action the canvas has already accepted. Layers have
/// no hit-testing or accessibility element, and never redraw the document.
@MainActor
final class LeadSheetCanvasTapAcknowledgement {
    static let duration: TimeInterval = 0.34
    static let actionBlue = IChartInterfaceStyle.actionUIColor
    static let confirmationGold = UIColor(red: 0.86, green: 0.62, blue: 0.18, alpha: 1)

    let layer = CALayer()
    private let ringEdge = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let checkEdge = CAShapeLayer()
    private let check = CAShapeLayer()
    private var removal: DispatchWorkItem?
    private(set) var snapshot: LeadSheetCanvasTapAcknowledgementSnapshot?
    private(set) var presentationCount: UInt64 = 0

    init() {
        layer.name = "LeadSheetAcceptedTapAcknowledgement"
        layer.zPosition = 1_000
        for shape in [ringEdge, ring, checkEdge, check] {
            shape.fillColor = UIColor.clear.cgColor
            shape.lineCap = .round
            shape.lineJoin = .round
            layer.addSublayer(shape)
        }
        ringEdge.strokeColor = UIColor.white.cgColor
        ring.strokeColor = Self.actionBlue.cgColor
        checkEdge.strokeColor = UIColor.white.cgColor
        check.strokeColor = Self.confirmationGold.cgColor
    }

    func present(at center: CGPoint, in parent: CALayer,
        screenPointsPerDisplayedPoint: CGFloat,
        reducesMotion: Bool = UIAccessibility.isReduceMotionEnabled) {
        guard center.x.isFinite, center.y.isFinite else { return }
        let scale = screenPointsPerDisplayedPoint.isFinite && screenPointsPerDisplayedPoint > 0
            ? screenPointsPerDisplayedPoint : 1
        let unit = 1 / scale
        let size = CGSize(width: 28 * unit, height: 28 * unit)
        removal?.cancel()
        layer.removeAllAnimations()
        presentationCount &+= 1
        let sequence = presentationCount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: size)
        layer.position = center
        let circle = UIBezierPath(ovalIn: CGRect(x: 4 * unit, y: 4 * unit,
            width: 20 * unit, height: 20 * unit)).cgPath
        ringEdge.path = circle
        ring.path = circle
        ringEdge.lineWidth = 5 * unit
        ring.lineWidth = 2.5 * unit
        let tick = UIBezierPath()
        tick.move(to: CGPoint(x: 9 * unit, y: 14 * unit))
        tick.addLine(to: CGPoint(x: 12.5 * unit, y: 17.5 * unit))
        tick.addLine(to: CGPoint(x: 19 * unit, y: 10.5 * unit))
        checkEdge.path = tick.cgPath
        check.path = tick.cgPath
        checkEdge.lineWidth = 5 * unit
        check.lineWidth = 2.5 * unit
        layer.opacity = reducesMotion ? 1 : 0
        if layer.superlayer !== parent { parent.addSublayer(layer) }
        snapshot = LeadSheetCanvasTapAcknowledgementSnapshot(center: center,
            frame: layer.frame, reducesMotion: reducesMotion, sequence: sequence)
        CATransaction.commit()
        if !reducesMotion {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.4, 1]
            fade.duration = Self.duration
            layer.add(fade, forKey: "acceptedTapFade")
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.snapshot?.sequence == sequence else { return }
            self.dismiss()
        }
        removal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration, execute: work)
    }

    func dismiss() {
        removal?.cancel()
        removal = nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        snapshot = nil
        CATransaction.commit()
    }
}
#endif

#if canImport(UIKit)
import UIKit

protocol LeadSheetDocumentInputRouting: AnyObject {
    func allowsDocumentVerticalScrollStart(at point: CGPoint, touchType: UITouch.TouchType) -> Bool
}

/// A changing viewport onto one logical document. Only this scroll view owns
/// zoom and scroll offsets; the supplied drawing view keeps paper coordinates.
final class LeadSheetDocumentViewport: UIScrollView, UIScrollViewDelegate {
    let documentView: UIView
    let documentContainerView = UIView()
    /// Refresh raster sharpness only when navigation has settled. The native
    /// scroll view composites the existing document throughout the gesture.
    var onZoomChanged: ((CGFloat) -> Void)?

    private(set) var documentID: UUID?
    private(set) var documentSize = CGSize.zero
    private(set) var fitWidthScale: CGFloat = 1
    private(set) var userZoomFactor: CGFloat = 1

    private var settledViewportSize: CGSize?
    private var retainedFocalPoint: CGPoint?
    private var lastObservedFocalPoint: CGPoint?
    private var needsDocumentLayout = false
    private var resetsViewportOnNextLayout = false
    private var isApplyingViewportGeometry = false
    private var hasActiveZoomInteraction = false
    private var hasActivePanInteraction = false
    private var hasActiveVerticalScrollInteraction = false
    private var isWaitingForDeceleration = false
    private var hasPendingDocumentDisplayRefresh = false
    private var verticalScrollStartingOffset = CGPoint.zero
    private var verticalScrollStartWasAccepted = false
    private let verticalScrollGestureDelegate = VerticalScrollGestureDelegate()
    private lazy var documentVerticalScrollRecognizer: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDocumentVerticalScroll(_:)))
        pan.name = "LeadSheetDocumentVerticalScroll"
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pan.requiresExclusiveTouchType = true
        pan.delegate = verticalScrollGestureDelegate
        return pan
    }()

    init(documentView: UIView) {
        self.documentView = documentView
        super.init(frame: .zero)
        verticalScrollGestureDelegate.viewport = self
        delegate = self
        backgroundColor = .clear
        isOpaque = false
        clipsToBounds = true
        bounces = false
        bouncesZoom = false
        delaysContentTouches = false
        canCancelContentTouches = true
        alwaysBounceHorizontal = false
        alwaysBounceVertical = false
        contentInsetAdjustmentBehavior = .never
        documentContainerView.backgroundColor = .clear
        documentContainerView.isOpaque = false
        documentContainerView.autoresizesSubviews = false
        addSubview(documentContainerView)
        documentContainerView.addSubview(documentView)
        addGestureRecognizer(documentVerticalScrollRecognizer)
        configureDirectTouchNavigation(interactionMode: .browse)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("Use init(documentView:).")
    }

    func update(documentID: UUID, documentSize: CGSize, interactionMode: EditorCanvasMode) {
        configureDirectTouchNavigation(interactionMode: interactionMode)
        guard Self.isValidSize(documentSize) else { return }

        let isNewDocument = self.documentID != documentID
        let hasDocumentSizeChange = self.documentSize != documentSize
        guard isNewDocument || hasDocumentSizeChange else { return }

        self.documentID = documentID
        self.documentSize = documentSize
        needsDocumentLayout = true
        if isNewDocument {
            hasActiveZoomInteraction = false
            hasActivePanInteraction = false
            hasActiveVerticalScrollInteraction = false
            isWaitingForDeceleration = false
            hasPendingDocumentDisplayRefresh = false
            userZoomFactor = 1
            retainedFocalPoint = nil
            lastObservedFocalPoint = nil
            resetsViewportOnNextLayout = true
        }
        setNeedsLayout()
        if Self.isValidSize(bounds.size) {
            layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !isApplyingViewportGeometry, Self.isValidSize(bounds.size),
              Self.isValidSize(documentSize) else { return }

        if needsDocumentLayout || settledViewportSize != bounds.size {
            applyViewportGeometry()
        } else {
            recordSettledViewportState()
        }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        documentContainerView
    }

    func requestDocumentDisplayRefresh() {
        hasPendingDocumentDisplayRefresh = true
        refreshDocumentDisplayIfSettled()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        guard !isApplyingViewportGeometry else { return }
        // A fresh pinch can interrupt momentum without a later deceleration
        // callback. Keep the new pinch active but release that stale wait.
        if !scrollView.isDecelerating {
            isWaitingForDeceleration = false
        }
        hasActiveZoomInteraction = true
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        guard !isApplyingViewportGeometry else { return }
        hasActiveZoomInteraction = false
        recordSettledViewportState()
        requestDocumentDisplayRefresh()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        hasActivePanInteraction = true
        isWaitingForDeceleration = false
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        hasActivePanInteraction = false
        isWaitingForDeceleration = decelerate
        refreshDocumentDisplayIfSettled()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isWaitingForDeceleration = false
        recordSettledViewportState()
        refreshDocumentDisplayIfSettled()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // An interrupted gesture must not defer display refresh forever
            // when SwiftUI later reattaches the same document viewport.
            hasActiveZoomInteraction = false
            hasActivePanInteraction = false
            hasActiveVerticalScrollInteraction = false
            isWaitingForDeceleration = false
        } else {
            refreshDocumentDisplayIfSettled()
        }
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        recordSettledViewportState()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // UIKit may notify delegates after changing bounds but before our next
        // layout. Keep the old paper focus until that viewport transition ends.
        guard !isApplyingViewportGeometry,
              !needsDocumentLayout,
              settledViewportSize == bounds.size,
              fitWidthScale > 0 else { return }

        let focalPoint = currentFocalPoint()
        isApplyingViewportGeometry = true
        updateScaledContentAndInsets()
        restoreFocalPoint(focalPoint)
        isApplyingViewportGeometry = false
        recordSettledViewportState()
        requestDocumentDisplayRefresh()
    }

    private func applyViewportGeometry() {
        let viewportSize = bounds.size
        let proposedFitScale = viewportSize.width / documentSize.width
        guard proposedFitScale.isFinite, proposedFitScale > 0 else { return }
        let minimumScale = proposedFitScale * 0.25
        let maximumScale = proposedFitScale * 4
        let proposedZoomScale = proposedFitScale * userZoomFactor
        guard minimumScale.isFinite, minimumScale > 0,
              maximumScale.isFinite, maximumScale > 0,
              proposedZoomScale.isFinite else { return }

        let focalPoint = retainedFocalPoint
        let resetsToTop = resetsViewportOnNextLayout || settledViewportSize == nil
        isApplyingViewportGeometry = true

        // The container alone is transformed by UIScrollView. Never assign a
        // transformed frame or change the drawing view's logical coordinates.
        documentContainerView.bounds = CGRect(origin: .zero, size: documentSize)
        documentView.frame = CGRect(origin: .zero, size: documentSize)
        fitWidthScale = proposedFitScale

        // Widen the range before installing the new limits: changing a limit
        // can itself clamp zoomScale and synchronously notify the delegate.
        minimumZoomScale = min(minimumZoomScale, minimumScale)
        maximumZoomScale = max(maximumZoomScale, maximumScale)
        let targetZoomScale = min(maximumScale, max(minimumScale, proposedZoomScale))
        setZoomScale(targetZoomScale, animated: false)
        minimumZoomScale = minimumScale
        maximumZoomScale = maximumScale
        // UIKit creates the native pinch recognizer only after zoom is enabled.
        // Apply its touch filters on the first layout, before any model echo.
        configureDirectPinchNavigation()
        updateScaledContentAndInsets()

        if resetsToTop || focalPoint == nil {
            setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
        } else if let focalPoint {
            restoreFocalPoint(focalPoint)
        }

        settledViewportSize = viewportSize
        needsDocumentLayout = false
        resetsViewportOnNextLayout = false
        isApplyingViewportGeometry = false
        recordSettledViewportState()
        requestDocumentDisplayRefresh()
    }

    private func refreshDocumentDisplayIfSettled() {
        guard hasPendingDocumentDisplayRefresh,
              !isApplyingViewportGeometry,
              !hasActiveZoomInteraction,
              !hasActivePanInteraction,
              !hasActiveVerticalScrollInteraction,
              !isWaitingForDeceleration else { return }
        hasPendingDocumentDisplayRefresh = false
        onZoomChanged?(zoomScale)
    }

    private func updateScaledContentAndInsets() {
        let scaledSize = CGSize(width: documentSize.width * zoomScale,
            height: documentSize.height * zoomScale)
        // Keep the zoomed container's frame origin at zero. Centering belongs
        // solely to the insets, so focal-point math uses one coordinate space.
        documentContainerView.center = CGPoint(x: scaledSize.width / 2, y: scaledSize.height / 2)
        if contentSize != scaledSize {
            contentSize = scaledSize
        }
        let horizontalInset = max(0, (bounds.width - scaledSize.width) / 2)
        let verticalInset = max(0, (bounds.height - scaledSize.height) / 2)
        let centeredInsets = UIEdgeInsets(top: verticalInset, left: horizontalInset,
            bottom: verticalInset, right: horizontalInset)
        if contentInset != centeredInsets {
            contentInset = centeredInsets
        }
    }

    private func currentFocalPoint() -> CGPoint {
        CGPoint(x: (contentOffset.x + bounds.width / 2) / zoomScale,
            y: (contentOffset.y + bounds.height / 2) / zoomScale)
    }

    private func restoreFocalPoint(_ focalPoint: CGPoint) {
        let proposedOffset = CGPoint(x: focalPoint.x * zoomScale - bounds.width / 2,
            y: focalPoint.y * zoomScale - bounds.height / 2)
        let minimumX = -contentInset.left
        let minimumY = -contentInset.top
        let maximumX = max(minimumX, contentSize.width - bounds.width + contentInset.right)
        let maximumY = max(minimumY, contentSize.height - bounds.height + contentInset.bottom)
        let offset = CGPoint(x: min(maximumX, max(minimumX, proposedOffset.x)),
            y: min(maximumY, max(minimumY, proposedOffset.y)))
        if contentOffset != offset {
            setContentOffset(offset, animated: false)
        }
        // Native scrolling can round an offset to the display's pixel grid.
        // Keep the requested paper focus across later geometry updates;
        // otherwise each rounded restoration becomes the next target and
        // repeated toolbar/rotation changes accumulate camera drift.
        let actualFocalPoint = currentFocalPoint()
        retainedFocalPoint = CGPoint(
            x: offset.x == proposedOffset.x ? focalPoint.x : actualFocalPoint.x,
            y: offset.y == proposedOffset.y ? focalPoint.y : actualFocalPoint.y)
        lastObservedFocalPoint = actualFocalPoint
    }

    private func recordSettledViewportState() {
        guard !isApplyingViewportGeometry,
              !needsDocumentLayout,
              settledViewportSize == bounds.size,
              zoomScale.isFinite, zoomScale > 0,
              fitWidthScale.isFinite, fitWidthScale > 0 else { return }
        let actualFocalPoint = currentFocalPoint()
        // A genuine scroll or native zoom establishes a new camera intent.
        // Unchanged passive layout must preserve the logical focus retained
        // above instead of adopting the same pixel-rounded offset again.
        if retainedFocalPoint == nil || lastObservedFocalPoint != actualFocalPoint {
            retainedFocalPoint = actualFocalPoint
        }
        lastObservedFocalPoint = actualFocalPoint
        userZoomFactor = min(4, max(0.25, zoomScale / fitWidthScale))
    }

    private func configureDirectTouchNavigation(interactionMode: EditorCanvasMode) {
        let directTouches = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        let minimumTouches = 2
        let pan = panGestureRecognizer
        // Preserve an external scroll lock. Only touch-routing configuration is
        // ours; isEnabled and isScrollEnabled belong to the active interaction.
        if pan.maximumNumberOfTouches < minimumTouches {
            pan.maximumNumberOfTouches = minimumTouches
        }
        if pan.minimumNumberOfTouches != minimumTouches {
            pan.minimumNumberOfTouches = minimumTouches
        }
        if pan.maximumNumberOfTouches != 2 {
            pan.maximumNumberOfTouches = 2
        }
        if pan.allowedTouchTypes != directTouches {
            pan.allowedTouchTypes = directTouches
        }
        if !pan.requiresExclusiveTouchType {
            pan.requiresExclusiveTouchType = true
        }
        configureDirectPinchNavigation()
    }

    private func allowsVerticalScrollTouch(_ gestureRecognizer: UIGestureRecognizer, touch: UITouch) -> Bool {
        guard gestureRecognizer === documentVerticalScrollRecognizer,
              touch.type == .direct || touch.type == .pencil,
              isScrollEnabled, panGestureRecognizer.isEnabled,
              bounds.contains(touch.location(in: self)) else { return false }
        let documentPoint = touch.location(in: documentView)
        let accepted = (documentView as? LeadSheetDocumentInputRouting)?
            .allowsDocumentVerticalScrollStart(at: documentPoint, touchType: touch.type) ?? true
        verticalScrollStartWasAccepted = accepted
        return accepted
    }

    private func shouldBeginVerticalScroll(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === documentVerticalScrollRecognizer else { return false }
        let velocity = documentVerticalScrollRecognizer.velocity(in: self)
        return verticalScrollStartWasAccepted && isScrollEnabled && panGestureRecognizer.isEnabled
            && documentVerticalScrollRecognizer.numberOfTouches <= 1
            && abs(velocity.y) > abs(velocity.x)
    }

    private func allowsSimultaneousVerticalScroll(_ gestureRecognizer: UIGestureRecognizer,
        otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === documentVerticalScrollRecognizer
                || otherGestureRecognizer === documentVerticalScrollRecognizer else { return false }
        let other = gestureRecognizer === documentVerticalScrollRecognizer ? otherGestureRecognizer : gestureRecognizer
        // A second direct finger hands navigation to UIKit's native pan/pinch.
        // Ink and rendered-object recognizers keep exclusive ownership.
        return other === panGestureRecognizer || other === pinchGestureRecognizer
    }

    private final class VerticalScrollGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var viewport: LeadSheetDocumentViewport?

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            viewport?.allowsVerticalScrollTouch(gestureRecognizer, touch: touch) ?? false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            viewport?.shouldBeginVerticalScroll(gestureRecognizer) ?? false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            viewport?.allowsSimultaneousVerticalScroll(gestureRecognizer,
                otherGestureRecognizer: otherGestureRecognizer) ?? false
        }
    }

    @objc func handleDocumentVerticalScroll(_ gesture: UIPanGestureRecognizer) {
        guard isScrollEnabled, panGestureRecognizer.isEnabled else {
            verticalScrollStartWasAccepted = false
            hasActiveVerticalScrollInteraction = false
            refreshDocumentDisplayIfSettled()
            return
        }
        switch gesture.state {
        case .began:
            verticalScrollStartingOffset = contentOffset
            setContentOffset(contentOffset, animated: false)
            hasActiveVerticalScrollInteraction = true
            isWaitingForDeceleration = false
        case .changed:
            if gesture.numberOfTouches > 1 { return }
            let inset = adjustedContentInset
            let minimumY = -inset.top
            let maximumY = max(minimumY, contentSize.height - bounds.height + inset.bottom)
            let appliedTranslation = gesture.translation(in: self)
            let y = min(maximumY, max(minimumY,
                verticalScrollStartingOffset.y - appliedTranslation.y))
            setContentOffset(CGPoint(x: verticalScrollStartingOffset.x, y: y), animated: false)
        case .ended, .cancelled, .failed:
            verticalScrollStartWasAccepted = false
            hasActiveVerticalScrollInteraction = false
            refreshDocumentDisplayIfSettled()
        default:
            break
        }
    }

    private func configureDirectPinchNavigation() {
        let directTouches = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        if let pinch = pinchGestureRecognizer {
            if pinch.allowedTouchTypes != directTouches {
                pinch.allowedTouchTypes = directTouches
            }
            if !pinch.requiresExclusiveTouchType {
                pinch.requiresExclusiveTouchType = true
            }
        }
    }

    private static func isValidSize(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}
#endif

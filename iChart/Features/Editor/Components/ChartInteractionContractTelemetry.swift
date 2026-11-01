#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import CoreGraphics
import UIKit

/// Pure, bounded comparisons. Geometry and gesture paths are local inputs only;
/// an emitted observation contains fixed reasons and comparison counts.
enum ChartInteractionContractTelemetry {
    enum Contract: String {
        case keyboard = "editor.keyboard_reachability"
        case navigation = "editor.navigation_response"

        var operation: String { self == .keyboard ? "review" : "navigate" }
        var scope: String { self == .keyboard ? "chords" : "page" }
    }

    struct KeyboardAction: Equatable {
        var frameInWindow: CGRect?
        var movesWithScroll = true
        var isPresent = true
        var isRequired = true
        var isEnabled = true
    }

    struct KeyboardSnapshot: Equatable {
        var epoch: UUID
        var now: TimeInterval
        var windowBounds: CGRect
        var viewportInWindow: CGRect
        var keyboardInWindow: CGRect
        var focusedFieldInWindow: CGRect?
        var requiredActions: [KeyboardAction] = []
        var contentOffsetY: CGFloat
        var minimumOffsetY: CGFloat
        var maximumOffsetY: CGFloat
        var isForeground = true
        var hasCurrentKeyboardGeometry = true
        var isFirstResponder = true
        var isActivelyScrolling = false

        fileprivate var geometry: KeyboardGeometry {
            .init(windowBounds: windowBounds, viewport: viewportInWindow, keyboard: keyboardInWindow,
                field: focusedFieldInWindow, actions: requiredActions, offset: contentOffsetY,
                minimumOffset: minimumOffsetY, maximumOffset: maximumOffsetY)
        }
    }

    fileprivate struct KeyboardGeometry: Equatable {
        var windowBounds: CGRect
        var viewport: CGRect
        var keyboard: CGRect
        var field: CGRect?
        var actions: [KeyboardAction]
        var offset: CGFloat
        var minimumOffset: CGFloat
        var maximumOffset: CGFloat
    }

    /// Two stable observations after the complete keyboard/focus/layout epoch
    /// has settled. A transition, scroll or foreground gap restarts the dwell.
    struct KeyboardObservation {
        private var epoch: UUID?
        private var geometry: KeyboardGeometry?
        private var stableSince: TimeInterval?
        private var firstComparableAt: TimeInterval?
        private var lastObservedAt: TimeInterval?
        private var firstAssessment: LeadSheetInkFeatureContract.Assessment?
        private var emitted = false

        mutating func reset() { self = Self() }

        mutating func observe(_ snapshot: KeyboardSnapshot) -> LeadSheetInkFeatureContract.Assessment? {
            guard snapshot.now.isFinite, snapshot.isForeground, snapshot.hasCurrentKeyboardGeometry,
                  snapshot.isFirstResponder, !snapshot.isActivelyScrolling,
                  let assessment = keyboardAssessment(snapshot) else { reset(); return nil }
            if epoch != snapshot.epoch || geometry != snapshot.geometry
                || lastObservedAt.map({ snapshot.now < $0 }) == true {
                epoch = snapshot.epoch
                geometry = snapshot.geometry
                stableSince = snapshot.now
                firstComparableAt = nil
                firstAssessment = nil
                emitted = false
            }
            lastObservedAt = snapshot.now
            guard let stableSince, snapshot.now - stableSince >= 0.5 else { return nil }
            guard let firstComparableAt, firstAssessment == assessment else {
                firstComparableAt = snapshot.now
                firstAssessment = assessment
                return nil
            }
            guard !emitted, snapshot.now - firstComparableAt >= 0.1 else { return nil }
            emitted = true
            return assessment
        }
    }

    /// Reachability is existential over the legal scroll range. An enabled
    /// action below the current viewport is normal when scrolling can expose it.
    static func keyboardAssessment(_ snapshot: KeyboardSnapshot) -> LeadSheetInkFeatureContract.Assessment? {
        guard snapshot.isForeground, snapshot.hasCurrentKeyboardGeometry, snapshot.isFirstResponder,
              !snapshot.isActivelyScrolling,
              finite(snapshot.windowBounds), finite(snapshot.viewportInWindow), finite(snapshot.keyboardInWindow),
              let field = snapshot.focusedFieldInWindow, finite(field),
              [snapshot.contentOffsetY, snapshot.minimumOffsetY, snapshot.maximumOffsetY].allSatisfy(\.isFinite),
              snapshot.minimumOffsetY <= snapshot.maximumOffsetY, snapshot.requiredActions.count <= 32 else { return nil }
        let viewport = snapshot.viewportInWindow.intersection(snapshot.windowBounds)
        let keyboard = snapshot.keyboardInWindow.intersection(snapshot.windowBounds)
        guard finite(viewport), finite(keyboard) else { return nil }
        let fieldVisible = contains(viewport, field) && !occludes(keyboard, field)
        let required = snapshot.requiredActions.filter { $0.isRequired && $0.isEnabled }
        var reachable = 0
        for action in required {
            if !action.isPresent { continue }
            guard let frame = action.frameInWindow, finite(frame) else { return nil }
            if actionReachable(frame: frame, viewport: viewport, keyboard: keyboard,
                minimumDelta: action.movesWithScroll ? snapshot.minimumOffsetY - snapshot.contentOffsetY : 0,
                maximumDelta: action.movesWithScroll ? snapshot.maximumOffsetY - snapshot.contentOffsetY : 0) { reachable += 1 }
        }
        let matches = fieldVisible && reachable == required.count
        return .init(outcome: matches ? "passed" : "violated",
            reason: !fieldVisible ? "keyboard_focused_field_occluded"
                : (matches ? "keyboard_controls_reachable" : "keyboard_action_unreachable"),
            expectedCount: 1 + required.count, actualCount: (fieldVisible ? 1 : 0) + reachable,
            contentMatches: matches)
    }

    enum GestureEnd { case ended, cancelled, failed, inProgress }

    struct NavigationSnapshot {
        var startingOffset: CGPoint
        var observedOffset: CGPoint
        var translation: CGPoint
        var contentHeight: CGFloat
        var viewportHeight: CGFloat
        var topInset: CGFloat = 0
        var bottomInset: CGFloat = 0
        var admitted = true
        var observedChange = true
        var end: GestureEnd = .ended
        var configurationIsStable = true
        var isForeground = true
        var wasLocked = false
        var handedOffToPanOrPinch = false
        var contactOwnedByInkOrControl = false
        var wasManipulatingObject = false
        var wasInteractionSuspended = false
        var wasFingerInking = false
        var maximumContactCount = 1
    }

    static func navigationAssessment(_ snapshot: NavigationSnapshot) -> LeadSheetInkFeatureContract.Assessment? {
        let values = [snapshot.startingOffset.x, snapshot.startingOffset.y,
            snapshot.observedOffset.x, snapshot.observedOffset.y, snapshot.translation.x,
            snapshot.translation.y, snapshot.contentHeight, snapshot.viewportHeight,
            snapshot.topInset, snapshot.bottomInset]
        guard values.allSatisfy(\.isFinite), snapshot.contentHeight >= 0, snapshot.viewportHeight > 0,
              snapshot.admitted, snapshot.observedChange, snapshot.end == .ended,
              snapshot.configurationIsStable, snapshot.isForeground, !snapshot.wasLocked,
              !snapshot.handedOffToPanOrPinch, !snapshot.contactOwnedByInkOrControl,
              !snapshot.wasManipulatingObject, !snapshot.wasInteractionSuspended, !snapshot.wasFingerInking,
              snapshot.maximumContactCount == 1,
              abs(snapshot.translation.y) > 1, abs(snapshot.translation.y) > abs(snapshot.translation.x) else { return nil }
        let minimum = -snapshot.topInset
        let maximum = max(minimum, snapshot.contentHeight - snapshot.viewportHeight + snapshot.bottomInset)
        let expectedY = min(maximum, max(minimum, snapshot.startingOffset.y - snapshot.translation.y))
        // A contact at a clamped edge or in an unscrollable viewport need not
        // produce movement. Do not manufacture an intent/failure from that.
        guard maximum - minimum > 1, abs(expectedY - snapshot.startingOffset.y) > 1 else { return nil }
        let matches = abs(snapshot.observedOffset.x - snapshot.startingOffset.x) <= 1
            && abs(snapshot.observedOffset.y - expectedY) <= 1
        return .init(outcome: matches ? "passed" : "violated",
            reason: matches ? "navigation_response_matches" : "navigation_offset_mismatch",
            expectedCount: 1, actualCount: matches ? 1 : 0, contentMatches: matches)
    }

    struct NavigationPolicySnapshot {
        var verticalMinimumContacts: Int
        var verticalMaximumContacts: Int
        var verticalAllowsDirectAndPencilOnly: Bool
        var verticalRequiresExclusiveTouch: Bool
        var hasExpectedRoutingDelegate: Bool
        var panMinimumContacts: Int
        var panMaximumContacts: Int
        var panAllowsDirectOnly: Bool
        var panRequiresExclusiveTouch: Bool
        var pinchAllowsDirectOnly: Bool
        var pinchRequiresExclusiveTouch: Bool
        var configurationIsComparable = true
        var isForeground = true
    }

    static func navigationPolicyAssessment(_ snapshot: NavigationPolicySnapshot) -> LeadSheetInkFeatureContract.Assessment? {
        guard snapshot.configurationIsComparable, snapshot.isForeground,
              (0...16).contains(snapshot.verticalMinimumContacts), (0...16).contains(snapshot.verticalMaximumContacts),
              (0...16).contains(snapshot.panMinimumContacts), (0...16).contains(snapshot.panMaximumContacts) else { return nil }
        let checks = [snapshot.verticalMinimumContacts == 1 && snapshot.verticalMaximumContacts == 1,
            snapshot.verticalAllowsDirectAndPencilOnly, snapshot.verticalRequiresExclusiveTouch,
            snapshot.hasExpectedRoutingDelegate, snapshot.panMinimumContacts == 2 && snapshot.panMaximumContacts == 2,
            snapshot.panAllowsDirectOnly, snapshot.panRequiresExclusiveTouch,
            snapshot.pinchAllowsDirectOnly, snapshot.pinchRequiresExclusiveTouch]
        let actual = checks.filter { $0 }.count
        return .init(outcome: actual == checks.count ? "passed" : "violated",
            reason: actual == checks.count ? "navigation_response_matches" : "navigation_policy_mismatch",
            expectedCount: checks.count, actualCount: actual, contentMatches: actual == checks.count)
    }

    static func properties(for assessment: LeadSheetInkFeatureContract.Assessment, contract: Contract,
        operationID: UUID, layoutStyle: String? = nil, durationMilliseconds: Double? = nil) -> IChartTelemetryProperties {
        var values = assessment.telemetryProperties
        values["contract_id"] = .string(contract.rawValue)
        values["contract_version"] = .int(1)
        values["operation_id"] = .string(operationID.uuidString.lowercased())
        values["operation"] = .string(contract.operation)
        values["scope"] = .string(contract.scope)
        if let layoutStyle { values["layout_style"] = .string(layoutStyle) }
        if let durationMilliseconds, durationMilliseconds.isFinite, durationMilliseconds >= 0 {
            values["duration_ms"] = .double(min(durationMilliseconds, 86_400_000))
        }
        return values
    }

    private static func actionReachable(frame: CGRect, viewport: CGRect, keyboard: CGRect,
        minimumDelta: CGFloat, maximumDelta: CGFloat) -> Bool {
        guard frame.minX >= viewport.minX - 1, frame.maxX <= viewport.maxX + 1,
              frame.height <= viewport.height + 2 else { return false }
        let low = max(minimumDelta, frame.maxY - viewport.maxY - 1)
        let high = min(maximumDelta, frame.minY - viewport.minY + 1)
        guard low <= high else { return false }
        guard frame.maxX > keyboard.minX && frame.minX < keyboard.maxX else { return true }
        // A docked, split or floating keyboard is an obstacle, not an assumed
        // full-width rectangle above which every control must be forced.
        return max(low, frame.maxY - keyboard.minY - 1) <= high
            || low <= min(high, frame.minY - keyboard.maxY + 1)
    }

    private static func finite(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && rect.width > 0 && rect.height > 0
            && [rect.minX, rect.minY, rect.width, rect.height].allSatisfy(\.isFinite)
    }
    private static func contains(_ outer: CGRect, _ inner: CGRect) -> Bool {
        outer.insetBy(dx: -1, dy: -1).contains(inner)
    }
    private static func occludes(_ obstacle: CGRect, _ frame: CGRect) -> Bool {
        let overlap = obstacle.intersection(frame)
        return !overlap.isNull && overlap.width > 1 && overlap.height > 1
    }
}

/// Opt-in observer owned by a chart review/correction scroll marker. It never
/// requests focus, scrolls content, reads field text, or registers touch input.
@MainActor
final class ChartKeyboardContractProbe: NSObject {
    private weak var scrollView: UIScrollView?
    private var keyboardFrame: CGRect?
    private var keyboardWindowBounds: CGRect?
    private var keyboardOrientation: UIInterfaceOrientation?
    private var epoch = UUID()
    private var epochStartedAt = ProcessInfo.processInfo.systemUptime
    private var authorization: IChartTelemetry.DiagnosticAuthorization?
    private var observation = ChartInteractionContractTelemetry.KeyboardObservation()
    private var workItem: DispatchWorkItem?
    private var samplesRemaining = 0
    private var completedEpoch: UUID?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init()
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification] {
            center.addObserver(self, selector: #selector(keyboardChanged(_:)), name: name, object: nil)
        }
        for name in [UIResponder.keyboardDidHideNotification, UIApplication.willResignActiveNotification] {
            center.addObserver(self, selector: #selector(invalidateKeyboard), name: name, object: nil)
        }
        for name in [UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                     UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification] {
            center.addObserver(self, selector: #selector(focusChanged(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(becameActive),
            name: UIApplication.didBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(registeredActionChanged(_:)),
            name: ChartKeyboardActionProbeView.stateChangedNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func stop() {
        workItem?.cancel()
        workItem = nil
        keyboardFrame = nil
        keyboardWindowBounds = nil
        scrollView = nil
        authorization = nil
        observation.reset()
        epoch = UUID()
        NotificationCenter.default.removeObserver(self)
    }

    func requestObservation() {
        guard workItem == nil, completedEpoch != epoch, keyboardFrame != nil,
              let scrollView, scrollView.window != nil,
              let current = IChartTelemetry.diagnosticAuthorization() else { return }
        if let authorization, !authorization.matches(current) {
            // The keyboard frame belonged to an earlier grant. A later opt-in
            // requires a fresh keyboard notification, not promotion of it.
            invalidateKeyboard()
            return
        }
        authorization = current
        samplesRemaining = 30
        scheduleSample(after: 0)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let current = IChartTelemetry.diagnosticAuthorization(), let window = scrollView?.window,
              let screenFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else {
            invalidateKeyboard(); return
        }
        keyboardFrame = window.convert(screenFrame, from: window.screen.coordinateSpace).intersection(window.bounds)
        keyboardWindowBounds = window.bounds
        keyboardOrientation = window.windowScene?.effectiveGeometry.interfaceOrientation
        beginEpoch(authorization: current)
    }

    @objc private func focusChanged(_ notification: Notification) {
        guard let current = IChartTelemetry.diagnosticAuthorization(),
              let view = notification.object as? UIView, let scrollView, view.isDescendant(of: scrollView) else { return }
        if let authorization, !authorization.matches(current) { invalidateKeyboard() }
        beginEpoch(authorization: current)
    }

    @objc private func registeredActionChanged(_ notification: Notification) {
        guard let current = IChartTelemetry.diagnosticAuthorization(),
              let marker = notification.object as? ChartKeyboardActionProbeView,
              let scrollView, marker.isDescendant(of: scrollView) else { return }
        // Explicit user scrolling owns its viewport. Recheck action/layout
        // changes only once an eligible focus/keyboard observation can settle.
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else {
            workItem?.cancel(); workItem = nil; observation.reset(); completedEpoch = epoch
            return
        }
        if let authorization, !authorization.matches(current) { invalidateKeyboard() }
        beginEpoch(authorization: current)
    }

    @objc private func invalidateKeyboard() {
        workItem?.cancel()
        workItem = nil
        keyboardFrame = nil
        keyboardWindowBounds = nil
        keyboardOrientation = nil
        authorization = nil
        observation.reset()
        epoch = UUID()
        completedEpoch = nil
    }

    @objc private func becameActive() {
        // A pre-background keyboard frame is unavailable until UIKit supplies
        // current screen geometry. Never count time spent in the background.
        invalidateKeyboard()
    }

    private func beginEpoch(authorization: IChartTelemetry.DiagnosticAuthorization) {
        workItem?.cancel()
        workItem = nil
        epoch = UUID()
        epochStartedAt = ProcessInfo.processInfo.systemUptime
        completedEpoch = nil
        observation.reset()
        self.authorization = authorization
        requestObservation()
    }

    private func scheduleSample(after delay: TimeInterval) {
        let expectedEpoch = epoch
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.epoch == expectedEpoch else { return }
            self.workItem = nil
            self.sample()
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func sample() {
        guard samplesRemaining > 0, let authorization, authorization.isCurrent,
              let scrollView, let window = scrollView.window,
              UIApplication.shared.applicationState == .active,
              window.windowScene?.activationState == .foregroundActive,
              keyboardWindowBounds == window.bounds,
              keyboardOrientation == window.windowScene?.effectiveGeometry.interfaceOrientation,
              let keyboardFrame else { invalidateKeyboard(); return }
        samplesRemaining -= 1
        // A finite traversal bounds diagnostics even for an unexpectedly large
        // view tree. Incomplete registration is unknown, never zero controls.
        var stack = scrollView.subviews
        var visited = 0
        var focusedField: UIView?
        var actions: [ChartInteractionContractTelemetry.KeyboardAction] = []
        while visited < 512, let view = stack.popLast() {
            visited += 1
            guard !view.isHidden, view.alpha > 0.01 else { continue }
            if view.isFirstResponder, view is UITextField || view is UITextView { focusedField = view }
            if let marker = view as? ChartKeyboardActionProbeView, marker.isRequiredForKeyboardTelemetry {
                actions.append(.init(frameInWindow: marker.convert(marker.bounds, to: window),
                    movesWithScroll: true, isEnabled: marker.isEnabledForKeyboardTelemetry))
            }
            stack.append(contentsOf: view.subviews)
        }
        guard stack.isEmpty, let focusedField, actions.count <= 32 else {
            observation.reset()
            if samplesRemaining > 0 { scheduleSample(after: 0.1) }
            return
        }
        let inset = scrollView.adjustedContentInset
        let sample = ChartInteractionContractTelemetry.KeyboardSnapshot(epoch: epoch,
            now: ProcessInfo.processInfo.systemUptime, windowBounds: window.bounds,
            viewportInWindow: scrollView.convert(scrollView.bounds, to: window), keyboardInWindow: keyboardFrame,
            focusedFieldInWindow: focusedField.convert(focusedField.bounds, to: window), requiredActions: actions,
            contentOffsetY: scrollView.contentOffset.y, minimumOffsetY: -inset.top,
            maximumOffsetY: max(-inset.top, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom),
            isActivelyScrolling: scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating)
        if let assessment = observation.observe(sample) {
            completedEpoch = epoch
            let operationID = epoch
            let observedDuration = (ProcessInfo.processInfo.systemUptime - epochStartedAt) * 1_000
            IChartTelemetry.recordDeferredDiagnostic("feature.contract_checked", chartID: nil,
                authorization: authorization) {
                ChartInteractionContractTelemetry.properties(for: assessment, contract: .keyboard,
                    operationID: operationID, durationMilliseconds: observedDuration)
            }
        } else if samplesRemaining > 0 { scheduleSample(after: 0.1) }
    }
}
#endif

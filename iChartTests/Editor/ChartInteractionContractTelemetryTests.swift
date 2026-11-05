#if canImport(UIKit) && canImport(PencilKit)
import XCTest
import UIKit
@testable import iChart

final class ChartInteractionContractTelemetryTests: XCTestCase {
    func testKeyboardRequiresSettlingAndTwoSeparatedStableSamples() {
        var observation = ChartInteractionContractTelemetry.KeyboardObservation()
        var sample = keyboard()
        XCTAssertNil(observation.observe(sample))
        sample.now = 0.49; XCTAssertNil(observation.observe(sample))
        sample.now = 0.501; XCTAssertNil(observation.observe(sample))
        sample.now = 0.55; XCTAssertNil(observation.observe(sample))
        sample.now = 0.602
        XCTAssertEqual(observation.observe(sample)?.reason, "keyboard_controls_reachable")
        sample.now = 1; XCTAssertNil(observation.observe(sample), "An unchanged epoch emits once")
    }

    func testKeyboardFieldMustActuallyFitAboveOcclusionAfterSettling() {
        var sample = keyboard()
        sample.focusedFieldInWindow = CGRect(x: 10, y: 590, width: 200, height: 44)
        let result = stableKeyboardResult(sample)
        XCTAssertEqual(result?.outcome, "violated")
        XCTAssertEqual(result?.reason, "keyboard_focused_field_occluded")
        XCTAssertEqual(result?.contentMatches, false)
    }

    func testOffscreenActionIsReachableThroughLegalScrollAndDoesNotFail() {
        var sample = keyboard()
        sample.requiredActions = [.init(frameInWindow: CGRect(x: 10, y: 1_100, width: 180, height: 44))]
        XCTAssertEqual(stableKeyboardResult(sample)?.outcome, "passed")
        sample.maximumOffsetY = 200
        XCTAssertEqual(stableKeyboardResult(sample)?.reason, "keyboard_action_unreachable")
    }

    func testFixedActionCannotBorrowScrollMovementAndDisabledActionIsExcluded() {
        var sample = keyboard()
        sample.requiredActions = [.init(frameInWindow: CGRect(x: 10, y: 700, width: 180, height: 44), movesWithScroll: false)]
        XCTAssertEqual(stableKeyboardResult(sample)?.reason, "keyboard_action_unreachable")
        sample.requiredActions[0].isEnabled = false
        XCTAssertEqual(stableKeyboardResult(sample)?.outcome, "passed")
        XCTAssertEqual(stableKeyboardResult(sample)?.expectedCount, 1)
    }

    func testEnablingAnUnreachableActionStartsNewObservationWithoutFocusOrKeyboardChange() {
        var sample = keyboard()
        sample.maximumOffsetY = sample.contentOffsetY
        sample.requiredActions = [.init(frameInWindow: CGRect(x: 10, y: 1_200, width: 180, height: 44), isEnabled: false)]
        var observation = ChartInteractionContractTelemetry.KeyboardObservation()
        _ = observation.observe(sample)
        sample.now = 0.501; _ = observation.observe(sample)
        sample.now = 0.602; XCTAssertEqual(observation.observe(sample)?.outcome, "passed")
        sample.requiredActions[0].isEnabled = true
        sample.now = 0.8; XCTAssertNil(observation.observe(sample))
        sample.now = 1.301; XCTAssertNil(observation.observe(sample))
        sample.now = 1.402
        XCTAssertEqual(observation.observe(sample)?.reason, "keyboard_action_unreachable")
    }

    func testFloatingKeyboardDoesNotInventFullWidthOcclusion() {
        var sample = keyboard()
        sample.keyboardInWindow = CGRect(x: 500, y: 200, width: 200, height: 250)
        sample.focusedFieldInWindow = CGRect(x: 10, y: 300, width: 200, height: 44)
        sample.requiredActions = [.init(frameInWindow: CGRect(x: 10, y: 400, width: 180, height: 44))]
        XCTAssertEqual(stableKeyboardResult(sample)?.outcome, "passed")
        sample.focusedFieldInWindow = CGRect(x: 510, y: 300, width: 180, height: 44)
        XCTAssertEqual(stableKeyboardResult(sample)?.reason, "keyboard_focused_field_occluded")
    }

    func testKeyboardFocusGeometryScrollAndForegroundChangesRestartTheWholeDwell() {
        for change in 0..<5 {
            var observation = ChartInteractionContractTelemetry.KeyboardObservation()
            var sample = keyboard()
            XCTAssertNil(observation.observe(sample))
            sample.now = 0.6; XCTAssertNil(observation.observe(sample))
            switch change {
            case 0: sample.epoch = UUID()
            case 1: sample.viewportInWindow.size.height -= 20
            case 2: sample.focusedFieldInWindow?.origin.y += 20
            case 3: sample.isActivelyScrolling = true
            default: sample.isForeground = false
            }
            sample.now = 0.8; XCTAssertNil(observation.observe(sample))
            sample.isActivelyScrolling = false; sample.isForeground = true
            sample.now = 1; XCTAssertNil(observation.observe(sample))
            sample.now = 1.501; XCTAssertNil(observation.observe(sample))
            sample.now = 1.602
            XCTAssertEqual(observation.observe(sample)?.outcome, "passed")
        }
    }

    func testKeyboardMissingOrNonfiniteGeometryRemainsUnknownAndWorkIsBounded() {
        var sample = keyboard()
        sample.hasCurrentKeyboardGeometry = false
        XCTAssertNil(stableKeyboardResult(sample))
        sample = keyboard(); sample.focusedFieldInWindow = nil
        XCTAssertNil(ChartInteractionContractTelemetry.keyboardAssessment(sample))
        sample = keyboard(); sample.keyboardInWindow = .null
        XCTAssertNil(ChartInteractionContractTelemetry.keyboardAssessment(sample))
        sample = keyboard(); sample.maximumOffsetY = -.infinity
        XCTAssertNil(ChartInteractionContractTelemetry.keyboardAssessment(sample))
        sample = keyboard(); sample.requiredActions = Array(repeating: .init(frameInWindow: CGRect(x: 10, y: 100, width: 50, height: 30)), count: 33)
        XCTAssertNil(ChartInteractionContractTelemetry.keyboardAssessment(sample))
    }

    func testAcceptedVerticalGestureMatchesClampedProductionOffsetAndPreservesX() {
        var sample = navigation()
        XCTAssertEqual(ChartInteractionContractTelemetry.navigationAssessment(sample)?.outcome, "passed")
        sample.translation.y = -20_000; sample.observedOffset.y = 1_430
        XCTAssertEqual(ChartInteractionContractTelemetry.navigationAssessment(sample)?.outcome, "passed")
        sample.observedOffset.x += 5
        XCTAssertEqual(ChartInteractionContractTelemetry.navigationAssessment(sample)?.reason, "navigation_offset_mismatch")
    }

    func testAcceptedNoResponseIsViolationButEdgeNoopIsNot() {
        var sample = navigation(); sample.observedOffset = sample.startingOffset
        let result = ChartInteractionContractTelemetry.navigationAssessment(sample)
        XCTAssertEqual(result?.outcome, "violated")
        XCTAssertEqual(result?.expectedCount, 1)
        XCTAssertEqual(result?.actualCount, 0)
        XCTAssertEqual(result?.contentMatches, false)
        sample.startingOffset.y = -20; sample.observedOffset.y = -20; sample.translation.y = 100
        XCTAssertNil(ChartInteractionContractTelemetry.navigationAssessment(sample))
    }

    func testNavigationExcludesUnknownIntentAndInterruptedOrChangedConfiguration() {
        for index in 0..<14 {
            var sample = navigation()
            switch index {
            case 0: sample.admitted = false
            case 1: sample.observedChange = false
            case 2: sample.end = .cancelled
            case 3: sample.end = .failed
            case 4: sample.configurationIsStable = false
            case 5: sample.isForeground = false
            case 6: sample.wasLocked = true
            case 7: sample.handedOffToPanOrPinch = true
            case 8: sample.contactOwnedByInkOrControl = true
            case 9: sample.wasManipulatingObject = true
            case 10: sample.wasInteractionSuspended = true
            case 11: sample.wasFingerInking = true
            case 12: sample.maximumContactCount = 2
            default: sample.translation = CGPoint(x: 140, y: 10)
            }
            XCTAssertNil(ChartInteractionContractTelemetry.navigationAssessment(sample), "Exclusion \(index)")
        }
    }

    func testNavigationRejectsNonfiniteAndUnscrollableObservations() {
        var sample = navigation(); sample.observedOffset.y = .nan
        XCTAssertNil(ChartInteractionContractTelemetry.navigationAssessment(sample))
        sample = navigation(); sample.contentHeight = 100
        sample.startingOffset.y = -20; sample.observedOffset.y = -20; sample.translation.y = 100
        XCTAssertNil(ChartInteractionContractTelemetry.navigationAssessment(sample))
    }

    func testNavigationPolicyIndependentlyDetectsTouchRoutingConfiguration() {
        var sample = policy()
        XCTAssertEqual(ChartInteractionContractTelemetry.navigationPolicyAssessment(sample)?.outcome, "passed")
        sample.verticalMinimumContacts = 2
        let result = ChartInteractionContractTelemetry.navigationPolicyAssessment(sample)
        XCTAssertEqual(result?.reason, "navigation_policy_mismatch")
        XCTAssertEqual(result?.expectedCount, 9)
        XCTAssertEqual(result?.actualCount, 8)
        sample = policy(); sample.verticalAllowsDirectAndPencilOnly = false
        XCTAssertEqual(ChartInteractionContractTelemetry.navigationPolicyAssessment(sample)?.contentMatches, false)
        sample.configurationIsComparable = false
        XCTAssertNil(ChartInteractionContractTelemetry.navigationPolicyAssessment(sample))
    }

    func testPropertiesCarryOnlyFixedContractEnumsAndComparisonEvidence() throws {
        var sample = navigation(); sample.observedOffset = sample.startingOffset
        let result = try XCTUnwrap(ChartInteractionContractTelemetry.navigationAssessment(sample))
        let operation = UUID()
        let values = ChartInteractionContractTelemetry.properties(for: result, contract: .navigation,
            operationID: operation, layoutStyle: "simpleChordSheet", durationMilliseconds: 123)
        XCTAssertEqual(values["contract_id"], .string("editor.navigation_response"))
        XCTAssertEqual(values["operation"], .string("navigate"))
        XCTAssertEqual(values["scope"], .string("page"))
        XCTAssertEqual(values["operation_id"], .string(operation.uuidString.lowercased()))
        let text = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        for forbidden in ["translation", "startingOffset", "observedOffset", "viewport", "keyboard", "raw_chord_text"] {
            XCTAssertFalse(text.contains(forbidden), forbidden)
        }
        let keyboard = ChartInteractionContractTelemetry.properties(for: result, contract: .keyboard,
            operationID: UUID())
        XCTAssertEqual(keyboard["operation"], .string("review"))
        XCTAssertEqual(keyboard["scope"], .string("chords"))
    }

    func testNativeInteractionAssessmentsExportSanitizedEndToEndFixtures() throws {
        var cases: [[String: Any]] = []
        let installation = UUID().uuidString.lowercased()
        let session = UUID().uuidString.lowercased()
        func append(_ name: String, assessment: LeadSheetInkFeatureContract.Assessment?,
            contract: ChartInteractionContractTelemetry.Contract, createsTask: Bool) throws {
            guard let assessment else {
                cases.append(["fixture": name, "event_emitted": false, "creates_task": false]); return
            }
            var input = ChartInteractionContractTelemetry.properties(for: assessment, contract: contract,
                operationID: UUID(), layoutStyle: "simpleChordSheet", durationMilliseconds: 602)
            input["build_source"] = .string("debug_build")
            let values = IChartTelemetryPrivacy.sanitizedProperties(input, forEventName: "feature.contract_checked")
            XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(values))
            XCTAssertEqual(values, input)
            let scalar = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values))
            cases.append(["fixture": name, "event_emitted": true, "creates_task": createsTask,
                "event": ["client_event_id": UUID().uuidString.lowercased(), "event_name": "feature.contract_checked",
                    "installation_id": installation, "session_id": session, "platform": "iPadOS",
                    "app_version": "internal-verification", "build_number": "0", "properties": scalar]])
        }
        try append("keyboard_reachable", assessment: stableKeyboardResult(keyboard()), contract: .keyboard, createsTask: false)
        var covered = keyboard(); covered.focusedFieldInWindow?.origin.y = 610
        try append("keyboard_field_occluded", assessment: stableKeyboardResult(covered), contract: .keyboard, createsTask: true)
        var unreachable = keyboard(); unreachable.maximumOffsetY = 100
        unreachable.requiredActions = [.init(frameInWindow: CGRect(x: 10, y: 1_200, width: 180, height: 44))]
        try append("keyboard_action_unreachable", assessment: stableKeyboardResult(unreachable), contract: .keyboard, createsTask: true)
        try append("navigation_response_matches", assessment: ChartInteractionContractTelemetry.navigationAssessment(navigation()),
            contract: .navigation, createsTask: false)
        var stalled = navigation(); stalled.observedOffset = stalled.startingOffset
        try append("navigation_no_response", assessment: ChartInteractionContractTelemetry.navigationAssessment(stalled),
            contract: .navigation, createsTask: true)
        var wrongPolicy = policy(); wrongPolicy.verticalMinimumContacts = 2
        try append("navigation_policy_mismatch", assessment: ChartInteractionContractTelemetry.navigationPolicyAssessment(wrongPolicy),
            contract: .navigation, createsTask: true)
        var edge = navigation(); edge.startingOffset.y = -20; edge.observedOffset.y = -20; edge.translation.y = 100
        try append("navigation_edge_control", assessment: ChartInteractionContractTelemetry.navigationAssessment(edge),
            contract: .navigation, createsTask: false)
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "scope": "Native synthetic interaction fixtures; fixed scalar telemetry only", "cases": cases],
            options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "chart-interaction-telemetry-native-e2e-fixtures"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testActualKeyboardProbeRechecksEnabledActionAndRejectsOldConsentDwell() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        previous?.endEditing(true)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller
        let trace = InteractionWindowNotificationTrace(window: window)
        window.makeKeyAndVisible()
        let recordingTrace = InteractionRecordingTraceRecorder()
        let fixture = try makeService(recordingObserver: { recordingTrace.record($0) })
        IChartTelemetry.configure(fixture.service)
        var expectedAuthorization = try XCTUnwrap(IChartTelemetry.diagnosticAuthorization())
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 50, width: 700, height: 400))
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.contentSize = CGSize(width: 700, height: 1_200)
        scroll.contentOffset = CGPoint(x: 0, y: 100)
        controller.view.addSubview(scroll)
        let field = UITextField(frame: CGRect(x: 10, y: 250, width: 200, height: 44))
        field.keyboardType = .asciiCapable
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .none
        scroll.addSubview(field)
        let action = ChartKeyboardActionProbeView(frame: CGRect(x: 10, y: 1_800, width: 180, height: 44))
        action.isRequiredForKeyboardTelemetry = true
        action.isEnabledForKeyboardTelemetry = false
        scroll.addSubview(action)
        let probe = ChartKeyboardContractProbe(scrollView: scroll)
        addTeardownBlock { @MainActor in
            trace.stop()
            probe.stop(); fixture.consent.setConsentGranted(false); IChartTelemetry.configure(nil)
            await fixture.service.consentDidChange()
            await fixture.consent.waitForPendingPersistence()
            fixture.session.invalidateAndCancel(); window.endEditing(true)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            UserDefaults.standard.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        // A UIWindowScene can replace a new window's initial bounds/orientation
        // on the next layout pass. Establish real focus only after the scene is
        // stable, then let UIKit deliver the keyboard geometry to production.
        try await waitForStableWindow(window, controller: controller)
        var probeSnapshots: [String] = []
        var previousProbeSnapshot = ""
        func captureProbeState() {
            let values = Dictionary(uniqueKeysWithValues: Mirror(reflecting: probe).children.compactMap { child in
                child.label.map { ($0, child.value) }
            })
            let capturedAuthorization = values["authorization"].flatMap { value in
                Mirror(reflecting: value).children.first?.value as? IChartTelemetry.DiagnosticAuthorization
            }
            let capturedOrientation = values["keyboardOrientation"].flatMap { value in
                Mirror(reflecting: value).children.first?.value as? UIInterfaceOrientation
            }
            let completedEpoch = values["completedEpoch"].flatMap { value in
                Mirror(reflecting: value).children.first?.value as? UUID
            }
            let currentAuthorization = IChartTelemetry.diagnosticAuthorization()
            var details = ["globalMatches=\(currentAuthorization?.matches(expectedAuthorization) == true)",
                "capturedMatches=\(capturedAuthorization?.matches(expectedAuthorization) == true)",
                "capturedCurrent=\(capturedAuthorization?.isCurrent == true)",
                "fixtureCurrent=\(expectedAuthorization.isCurrent)",
                "orientation=\(scene.effectiveGeometry.interfaceOrientation.rawValue)",
                "capturedOrientation=\(capturedOrientation.map { String($0.rawValue) } ?? "nil")",
                "persistedIdentity=\(UserDefaults(suiteName: fixture.suite)?.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey) != nil)"]
            if completedEpoch != nil, let health = try? fixture.queue.healthSnapshot() {
                details.append("queueHealth=\(health)")
            }
            for name in ["keyboardFrame", "keyboardWindowBounds", "epoch", "completedEpoch",
                         "samplesRemaining", "workItem", "observation"] {
                details.append("\(name)=\(values[name].map { String(describing: $0) } ?? "missing")")
            }
            let snapshot = details.joined(separator: "; ")
            if snapshot != previousProbeSnapshot {
                probeSnapshots.append("\(ProcessInfo.processInfo.systemUptime) \(snapshot)")
                if probeSnapshots.count > 100 { probeSnapshots.removeFirst(probeSnapshots.count - 100) }
                previousProbeSnapshot = snapshot
            }
        }
        let diagnostics = {
            "app=\(UIApplication.shared.applicationState.rawValue), scene=\(scene.activationState.rawValue), key=\(window.isKeyWindow), window=\(window.bounds), scroll=\(scroll.bounds), offset=\(scroll.contentOffset), field=\(field.convert(field.bounds, to: window)), focused=\(field.isFirstResponder), authorization=\(IChartTelemetry.diagnosticAuthorization() != nil)\nNotifications:\n\(trace.entries.joined(separator: "\n"))\nProbe snapshots:\n\(probeSnapshots.joined(separator: "\n"))\nDeferred recording:\n\(recordingTrace.entries.joined(separator: "\n"))"
        }
        addTeardownBlock { @MainActor in
            let attachment = XCTAttachment(string: diagnostics())
            attachment.name = "Interaction probe diagnostic timeline"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        var keyboardEventCount = trace.keyboardEventCount
        XCTAssertTrue(field.becomeFirstResponder())
        try await waitForKeyboard(visible: true, after: keyboardEventCount, field: field,
                                  window: window, trace: trace)
        _ = try await waitForEvents(fixture.queue, matching: { $0.properties["reason"] == .string("keyboard_controls_reachable") }, diagnostics: diagnostics, onPoll: captureProbeState)
        // Rechecking the registered action must not need a fresh focus or
        // keyboard event once the onscreen keyboard has settled.
        keyboardEventCount = trace.keyboardEventCount
        action.isEnabledForKeyboardTelemetry = true
        let failure = try await waitForEvents(fixture.queue,
            matching: { $0.properties["reason"] == .string("keyboard_action_unreachable") }, diagnostics: diagnostics, onPoll: captureProbeState)
        XCTAssertEqual(trace.keyboardEventCount, keyboardEventCount,
                       "The enabled-action change itself must trigger the recheck")
        XCTAssertEqual(failure.properties["expected_count"], .int(2))
        XCTAssertEqual(failure.properties["actual_count"], .int(1))

        action.isEnabledForKeyboardTelemetry = false
        keyboardEventCount = trace.keyboardEventCount
        fixture.consent.setConsentGranted(false)
        await fixture.service.consentDidChange()
        fixture.consent.setConsentGranted(true)
        await fixture.service.consentDidChange()
        expectedAuthorization = try XCTUnwrap(IChartTelemetry.diagnosticAuthorization())
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(trace.keyboardEventCount, keyboardEventCount,
                       "The withdrawal test must retain the earlier keyboard epoch")
        XCTAssertTrue(try fixture.queue.loadEvents().isEmpty, "The old keyboard epoch cannot adopt the new grant")
        XCTAssertTrue(field.resignFirstResponder())
        try await waitForKeyboard(visible: false, after: keyboardEventCount, field: field,
                                  window: window, trace: trace)
        keyboardEventCount = trace.keyboardEventCount
        XCTAssertTrue(field.becomeFirstResponder())
        try await waitForKeyboard(visible: true, after: keyboardEventCount, field: field,
                                  window: window, trace: trace)
        _ = try await waitForEvents(fixture.queue, matching: { $0.properties["reason"] == .string("keyboard_controls_reachable") }, diagnostics: diagnostics, onPoll: captureProbeState)
    }

    @MainActor
    private func waitForKeyboard(visible: Bool, after eventCount: Int, field: UITextField,
        window: UIWindow, trace: InteractionWindowNotificationTrace) async throws {
        // Keyboard startup is a separate UI readiness phase, not an extension
        // of the production telemetry event deadline below.
        for _ in 0..<160 {
            window.layoutIfNeeded()
            let hasFreshGeometry = trace.keyboardEventCount > eventCount
            if visible {
                if hasFreshGeometry, field.isFirstResponder, window.isKeyWindow,
                   let frame = trace.keyboardInWindow, frame.height >= 180,
                   let stableSince = trace.keyboardFrameStableSince,
                   ProcessInfo.processInfo.systemUptime - stableSince >= 0.2 { return }
            } else if hasFreshGeometry, !field.isFirstResponder, trace.keyboardInWindow == nil,
                      trace.lastKeyboardNotification == UIResponder.keyboardDidHideNotification {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The interaction fixture requires an actual \(visible ? "onscreen software keyboard" : "keyboard dismissal"); notifications: \(trace.entries)")
        throw InteractionFixtureError.keyboardUnavailable
    }

    @MainActor
    func testActualNavigationQueueUsesLastAppliedChangeAndIgnoresUnsettledPolicy() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController(); window.rootViewController = controller
        window.makeKeyAndVisible()
        let fixture = try makeService()
        let viewport = LeadSheetDocumentViewport(documentView: UIView())
        controller.view.addSubview(viewport)
        IChartTelemetry.configure(fixture.service)
        addTeardownBlock { @MainActor in
            fixture.consent.setConsentGranted(false); IChartTelemetry.configure(nil)
            await fixture.service.consentDidChange()
            await fixture.consent.waitForPendingPersistence()
            fixture.session.invalidateAndCancel(); window.endEditing(true)
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
            UserDefaults.standard.removePersistentDomain(forName: fixture.suite)
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        viewport.layoutSubviews() // Zero bounds and document are unavailable, not a broken policy.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(try fixture.queue.loadEvents().isEmpty)
        viewport.frame = controller.view.bounds
        viewport.update(documentID: UUID(), documentSize: CGSize(width: 932, height: 3_000), interactionMode: .chordEntry)
        viewport.layoutIfNeeded()
        viewport.setContentOffset(CGPoint(x: viewport.contentOffset.x, y: 200), animated: false)
        let start = viewport.contentOffset
        let vertical = try XCTUnwrap(viewport.gestureRecognizers?.first { $0.name == "LeadSheetDocumentVerticalScroll" })
        let touch = InteractionNavigationTouch(view: viewport)
        XCTAssertEqual(vertical.delegate?.gestureRecognizer?(vertical, shouldReceive: touch), true)
        let gesture = InteractionNavigationPan()
        gesture.fixtureState = .began; viewport.handleDocumentVerticalScroll(gesture)
        gesture.fixtureState = .changed; gesture.movement = CGPoint(x: 0, y: -140)
        viewport.handleDocumentVerticalScroll(gesture)
        XCTAssertEqual(viewport.contentOffset.y, start.y + 140, accuracy: 1)
        gesture.fixtureState = .ended; gesture.movement = CGPoint(x: 0, y: -155)
        viewport.handleDocumentVerticalScroll(gesture)
        XCTAssertEqual(viewport.contentOffset.y, start.y + 140, accuracy: 1)
        let event = try await waitForEvents(fixture.queue, matching: {
            $0.properties["contract_id"] == .string("editor.navigation_response")
                && $0.properties["expected_count"] == .int(1)
        })
        XCTAssertEqual(event.properties["outcome"], .string("passed"))
        XCTAssertEqual(event.properties["reason"], .string("navigation_response_matches"))
        XCTAssertFalse(try fixture.queue.loadEvents().contains { $0.properties["outcome"] == .string("violated") })
    }

    @MainActor
    private func makeService(recordingObserver: (@Sendable (IChartTelemetryRecordingTrace) -> Void)? = nil) throws
        -> (service: IChartTelemetryService, consent: IChartTelemetryConsentStore,
        queue: IChartTelemetryQueueStore, session: URLSession, directory: URL, suite: String) {
        let suite = "interaction-telemetry-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = IChartTelemetryQueueStore(url: directory.appendingPathComponent("queue.json"))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InteractionTelemetryOfflineProtocol.self]
        let session = URLSession(configuration: config)
        let service = IChartTelemetryService(endpointURL: URL(string: "https://telemetry.invalid/ingest")!,
            publishableKey: "synthetic", sessionStore: nil, queueStore: queue, consentStore: consent,
            urlSession: session, recordingObserver: recordingObserver)
        return (service, consent, queue, session, directory, suite)
    }

    @MainActor
    private func waitForStableWindow(_ window: UIWindow, controller: UIViewController) async throws {
        var previousBounds: CGRect?
        var previousOrientation: UIInterfaceOrientation?
        var stableSince: TimeInterval?
        for _ in 0..<80 {
            window.layoutIfNeeded()
            controller.view.layoutIfNeeded()
            let orientation = window.windowScene?.effectiveGeometry.interfaceOrientation
            let bounds = window.bounds
            let ready = window.isKeyWindow && window.windowScene?.activationState == .foregroundActive
                && UIApplication.shared.applicationState == .active
                && bounds.width > 0 && bounds.height > 0
                && controller.view.bounds.size == bounds.size
                && orientation != nil && orientation != .unknown
            let now = ProcessInfo.processInfo.systemUptime
            if ready, previousBounds == bounds, previousOrientation == orientation {
                if let stableSince, now - stableSince >= 0.2 { return }
                if stableSince == nil { stableSince = now }
            } else {
                stableSince = nil
            }
            previousBounds = bounds
            previousOrientation = orientation
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The interaction fixture requires a key foreground window with stable real scene geometry")
        throw InteractionFixtureError.unstableWindow
    }

    @MainActor
    private func waitForEvents(_ queue: IChartTelemetryQueueStore,
        matching predicate: (IChartTelemetryEvent) -> Bool,
        diagnostics: (() -> String)? = nil,
        onPoll: (() -> Void)? = nil,
        file: StaticString = #filePath, line: UInt = #line) async throws -> IChartTelemetryEvent {
        var observedReasons: Set<String> = []
        for _ in 0..<80 {
            onPoll?()
            let events = try queue.loadEvents()
            for event in events {
                if case let .string(reason)? = event.properties["reason"] { observedReasons.insert(reason) }
            }
            if let event = events.first(where: predicate) { return event }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let details = diagnostics?() ?? ""
        if !details.isEmpty {
            let attachment = XCTAttachment(string: details)
            attachment.name = "Interaction probe state at missing event"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTFail("The actual interaction hook must reach the production telemetry queue; observed reasons: \(observedReasons.sorted())\n\(details)",
                file: file, line: line)
        throw InteractionFixtureError.eventNotRecorded
    }

    private func keyboard() -> ChartInteractionContractTelemetry.KeyboardSnapshot {
        .init(epoch: UUID(), now: 0, windowBounds: CGRect(x: 0, y: 0, width: 800, height: 1_000),
            viewportInWindow: CGRect(x: 0, y: 60, width: 800, height: 900),
            keyboardInWindow: CGRect(x: 0, y: 600, width: 800, height: 400),
            focusedFieldInWindow: CGRect(x: 10, y: 200, width: 200, height: 44),
            requiredActions: [.init(frameInWindow: CGRect(x: 10, y: 500, width: 180, height: 44))],
            contentOffsetY: 100, minimumOffsetY: 0, maximumOffsetY: 900)
    }

    private func stableKeyboardResult(_ initial: ChartInteractionContractTelemetry.KeyboardSnapshot)
        -> LeadSheetInkFeatureContract.Assessment? {
        var sample = initial; var observation = ChartInteractionContractTelemetry.KeyboardObservation()
        _ = observation.observe(sample)
        sample.now += 0.501; _ = observation.observe(sample)
        sample.now += 0.101; return observation.observe(sample)
    }

    private func navigation() -> ChartInteractionContractTelemetry.NavigationSnapshot {
        .init(startingOffset: CGPoint(x: 70, y: 230), observedOffset: CGPoint(x: 70, y: 370),
            translation: CGPoint(x: 10, y: -140), contentHeight: 2_000, viewportHeight: 600,
            topInset: 20, bottomInset: 30)
    }

    private func policy() -> ChartInteractionContractTelemetry.NavigationPolicySnapshot {
        .init(verticalMinimumContacts: 1, verticalMaximumContacts: 1,
            verticalAllowsDirectAndPencilOnly: true, verticalRequiresExclusiveTouch: true,
            hasExpectedRoutingDelegate: true, panMinimumContacts: 2, panMaximumContacts: 2,
            panAllowsDirectOnly: true, panRequiresExclusiveTouch: true,
            pinchAllowsDirectOnly: true, pinchRequiresExclusiveTouch: true)
    }
}

private enum InteractionFixtureError: Error {
    case unstableWindow
    case keyboardUnavailable
    case eventNotRecorded
}

private final class InteractionRecordingTraceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var entries: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ trace: IChartTelemetryRecordingTrace) {
        var value = "\(ProcessInfo.processInfo.systemUptime) call=\(trace.callID.uuidString.prefix(8)) event=\(trace.eventName) stage=\(trace.stage.rawValue) main=\(Thread.isMainThread)"
        if let domain = trace.errorDomain, let code = trace.errorCode {
            value += " error=\(domain):\(code)"
        }
        if let denial = trace.admissionDenial {
            value += " admission=\(denial.rawValue)"
        }
        lock.lock()
        recorded.append(value)
        if recorded.count > 100 { recorded.removeFirst(recorded.count - 100) }
        lock.unlock()
    }
}

@MainActor private final class InteractionWindowNotificationTrace: NSObject {
    private weak var window: UIWindow?
    private(set) var entries: [String] = []
    private(set) var keyboardEventCount = 0
    private(set) var lastKeyboardNotification: Notification.Name?
    private(set) var keyboardInWindow: CGRect?
    private(set) var keyboardFrameStableSince: TimeInterval?
    init(window: UIWindow) {
        self.window = window
        super.init()
        for name in [UIResponder.keyboardDidShowNotification, UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardDidHideNotification, UIApplication.willResignActiveNotification,
                     UIApplication.didBecomeActiveNotification, UIWindow.didBecomeKeyNotification,
                     UIWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(observe(_:)), name: name, object: nil)
        }
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    func stop() { NotificationCenter.default.removeObserver(self) }
    @objc private func observe(_ note: Notification) {
        let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
        let now = ProcessInfo.processInfo.systemUptime
        if note.name == UIResponder.keyboardDidHideNotification {
            keyboardEventCount += 1
            lastKeyboardNotification = note.name
            keyboardInWindow = nil
            keyboardFrameStableSince = nil
        } else if let frame, let window {
            keyboardEventCount += 1
            lastKeyboardNotification = note.name
            let converted = window.convert(frame, from: window.screen.coordinateSpace).intersection(window.bounds)
            let visibleFrame = !converted.isNull && converted.height > 0 ? converted : nil
            if keyboardInWindow != visibleFrame { keyboardFrameStableSince = now }
            keyboardInWindow = visibleFrame
        }
        entries.append("\(now) \(note.name.rawValue), keyboard=\(String(describing: frame)), key=\(window?.isKeyWindow == true), bounds=\(String(describing: window?.bounds)), orientation=\(String(describing: window?.windowScene?.effectiveGeometry.interfaceOrientation.rawValue)), app=\(UIApplication.shared.applicationState.rawValue)")
        if entries.count > 40 { entries.removeFirst(entries.count - 40) }
    }
}

@MainActor private final class InteractionNavigationTouch: UITouch {
    private weak var fixtureView: UIView?
    init(view: UIView) { fixtureView = view; super.init() }
    override var type: UITouch.TouchType { .direct }
    override func location(in view: UIView?) -> CGPoint {
        guard let fixtureView else { return .zero }
        // UIScrollView's local bounds origin includes its content offset. A
        // visible synthetic contact must be inside those current bounds, not
        // the document origin above the scrolled viewport.
        let point = CGPoint(x: fixtureView.bounds.minX + 2,
            y: fixtureView.bounds.minY + min(100, fixtureView.bounds.height / 2))
        return fixtureView.convert(point, to: view)
    }
}

@MainActor private final class InteractionNavigationPan: UIPanGestureRecognizer {
    var fixtureState: UIGestureRecognizer.State = .possible
    var movement = CGPoint.zero
    override var state: UIGestureRecognizer.State { get { fixtureState } set { fixtureState = newValue } }
    override var numberOfTouches: Int { 1 }
    override func translation(in view: UIView?) -> CGPoint { movement }
}

private final class InteractionTelemetryOfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif

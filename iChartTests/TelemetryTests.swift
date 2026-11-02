import XCTest

#if canImport(UIKit)
@testable import iChart

final class TelemetryTests: XCTestCase {
    // Keep this value check on the startup projection actor. Background and
    // deferred-cleanup contention are exercised by the dedicated tests below.
    @MainActor
    func testTelemetryConsentDefaultsOffAndRejectsLegacyOrUnknownValues() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-telemetry-consent-\(UUID().uuidString)"))
        defaults.set(UUID().uuidString, forKey: IChartTelemetryConsentStore.installationIDPreferenceKey)
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertFalse(consent.snapshot.isGranted)
        await consent.waitForPendingPersistence()
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        for value in ["true", "telemetry-consent-v0", "telemetry-consent-v2"] {
            defaults.set(value, forKey: IChartTelemetryConsentStore.preferenceKey)
            XCTAssertFalse(consent.snapshot.isGranted)
            XCTAssertNil(consent.installationID(for: consent.snapshot))
        }
        consent.setConsentGranted(true)
        XCTAssertTrue(consent.snapshot.isGranted)
        XCTAssertEqual(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey), IChartTelemetryConsentStore.currentVersion)
    }

    func testInitializationWithCurrentPreferencesDoesNotProjectOrBlockAdmission() async throws {
        for isGranted in [false, true] {
            let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-consent-init-noop-\(UUID().uuidString)"))
            if isGranted {
                defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
            }
            var mutationCount = 0
            defaults.onMutation = { _ in mutationCount += 1 }
            let consent = IChartTelemetryConsentStore(defaults: defaults)
            let initial = consent.snapshot
            XCTAssertEqual(initial.isGranted, isGranted)
            if isGranted { XCTAssertEqual(consent.performIfGranted(matching: initial) { true }, true) }
            else { XCTAssertTrue(consent.clearQueuedEvents(matching: initial) {}) }
            // An explicit queue clear above is allowed to project its reset;
            // compare after it finishes so only queued initialization is tested.
            let explicitMutationCount = mutationCount

            await consent.waitForPendingPersistence()

            XCTAssertEqual(mutationCount, explicitMutationCount)
            if isGranted { XCTAssertEqual(mutationCount, 0) }
            XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
            defaults.onMutation = nil
        }
    }

    func testQueuedStartupProjectionReturnsMainWhileBackgroundCleanupIsBlocked() async throws {
        for isGranted in [true, false] {
            let gate = TelemetryStartupCleanupGate()
            let (consent, cleanup) = try await MainActor.run { () -> (IChartTelemetryConsentStore, Task<Void, Never>) in
                let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-needed-startup-projection-\(isGranted)-\(UUID().uuidString)"))
                if isGranted {
                    defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
                } else {
                    defaults.set(UUID().uuidString, forKey: IChartTelemetryConsentStore.installationIDPreferenceKey)
                }
                defaults.set(true, forKey: "iChart.telemetry.checkpoint-reset-required.v1")
                let consent = IChartTelemetryConsentStore(
                    defaults: defaults,
                    diagnosticFileURLs: [URL(fileURLWithPath: "/unused-startup-checkpoint")],
                    removeDiagnosticFile: { _ in try gate.blockWhenEnabled() }
                )
                // Finish any readback cleanup while it is allowed to succeed.
                // The initializer's main-queue projection remains queued.
                _ = consent.snapshot
                gate.enable()
                let cleanup = Task.detached {
                    if isGranted { consent.setConsentGranted(false) }
                    else { consent.retryDiagnosticCleanup() }
                }
                XCTAssertTrue(gate.waitUntilEntered())
                return (consent, cleanup)
            }
            let returned = expectation(description: "main scheduling returned during startup cleanup \(isGranted)")
            DispatchQueue.main.async {
                XCTAssertFalse(consent.cachedSnapshotForScheduling.isGranted)
                returned.fulfill()
            }

            await fulfillment(of: [returned], timeout: 1)

            gate.release()
            await cleanup.value
            await consent.waitForPendingPersistence()
            XCTAssertFalse(consent.snapshot.isGranted)
            XCTAssertNil(consent.checkpointAuthorization())
        }
    }

    func testTelemetryWithdrawalInvalidatesPriorConsentAndInstallationIdentity() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-telemetry-consent-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let originalConsent = consent.snapshot
        let originalID = try XCTUnwrap(consent.installationID(for: originalConsent))
        consent.setConsentGranted(false)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertNil(defaults.object(forKey: IChartTelemetryConsentStore.preferenceKey))
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        consent.setConsentGranted(true)
        XCTAssertNotEqual(consent.snapshot, originalConsent)
        XCTAssertNil(consent.performIfGranted(matching: originalConsent) { true })
        XCTAssertNotEqual(try XCTUnwrap(consent.installationID(for: consent.snapshot)), originalID)
    }

    func testQueueResetRemainsUntilSuccessfulCleanupForMatchingConsent() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-telemetry-reset-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let oldConsent = consent.snapshot
        consent.setConsentGranted(false)
        consent.setConsentGranted(true)
        let currentConsent = consent.snapshot
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertFalse(consent.clearQueuedEvents(matching: oldConsent) {
            XCTFail("An old consent generation must not clear the queue")
        })
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertThrowsError(try consent.clearQueuedEvents(matching: currentConsent) {
            throw NSError(domain: "TelemetryCleanupTest", code: 1)
        })
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertTrue(consent.clearQueuedEvents(matching: currentConsent) {})
        XCTAssertFalse(consent.requiresQueueReset)
    }

    func testAuthoritativeRefreshObservesRestoredResetMarkersWithoutConsentVersionChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "iChart-consent-restored-markers-\(UUID().uuidString)"))
        defaults.set(IChartTelemetryConsentStore.currentVersion, forKey: IChartTelemetryConsentStore.preferenceKey)
        let consent = IChartTelemetryConsentStore(
            defaults: defaults,
            diagnosticFileURLs: [URL(fileURLWithPath: "/unused-telemetry-checkpoint")],
            removeDiagnosticFile: { _ in throw NSError(domain: "CleanupTest", code: 1) }
        )
        XCTAssertFalse(consent.requiresQueueReset)
        XCTAssertFalse(consent.requiresDiagnosticCleanup)
        defaults.set(true, forKey: "iChart.telemetry.queue-reset-required.v1")
        defaults.set(true, forKey: "iChart.telemetry.checkpoint-reset-required.v1")

        XCTAssertTrue(consent.snapshot.isGranted)
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertTrue(consent.requiresDiagnosticCleanup)
        XCTAssertNil(consent.checkpointAuthorization())
    }

    func testPreferenceMutationCallbacksCanReenterConsentAndCheckpointReads() throws {
        let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-consent-reentry-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        var callbackCount = 0
        defaults.onMutation = { _ in
            XCTAssertTrue(Thread.isMainThread)
            _ = consent.snapshot
            _ = consent.requiresQueueReset
            _ = consent.requiresDiagnosticCleanup
            _ = consent.checkpointAuthorization()
            callbackCount += 1
        }

        consent.setConsentGranted(true)
        let granted = consent.snapshot
        XCTAssertNotNil(consent.installationID(for: granted))
        consent.setConsentGranted(false)

        XCTAssertGreaterThan(callbackCount, 0)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertNil(consent.checkpointAuthorization())
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        defaults.onMutation = nil
    }

    func testBackgroundPreferenceProjectionDoesNotBlockOrdinaryMainWithdrawal() async throws {
        let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-consent-cross-thread-reentry-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let grant = consent.snapshot
        let oldAuthorization = try XCTUnwrap(consent.checkpointAuthorization())
        let finished = expectation(description: "background projection completed")
        let withdrawn = expectation(description: "ordinary main withdrawal completed")
        let state = TelemetryPreferenceCallbackState()
        defaults.onMutation = { _ in
            XCTAssertTrue(Thread.isMainThread, "Every preference projection must write on main")
            guard state.beginCallback() else { return }
            let acknowledged = DispatchSemaphore(value: 0)
            let readAndAcknowledge = {
                _ = consent.snapshot
                _ = consent.checkpointAuthorization()
                acknowledged.signal()
            }
            if Thread.isMainThread {
                readAndAcknowledge()
                DispatchQueue.main.async {
                    consent.setConsentGranted(false)
                    withdrawn.fulfill()
                }
            } else {
                // Models a background preference notification waiting for a
                // main read while an ordinary Toggle withdrawal runs first.
                DispatchQueue.main.async {
                    consent.setConsentGranted(false)
                    withdrawn.fulfill()
                }
                DispatchQueue.main.async(execute: readAndAcknowledge)
                if acknowledged.wait(timeout: .now() + 1) != .success { state.recordTimeout() }
            }
        }
        DispatchQueue.global().async {
            XCTAssertTrue(consent.clearQueuedEvents(matching: grant) {})
            finished.fulfill()
        }

        await fulfillment(of: [finished, withdrawn], timeout: 5)

        defaults.onMutation = nil
        XCTAssertTrue(state.didReenter)
        XCTAssertFalse(state.didTimeout)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey))
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        XCTAssertNil(consent.performIfGranted(matching: grant) { true })
        XCTAssertFalse(try consent.publishDiagnosticCheckpoint(
            Data([1]), to: URL(fileURLWithPath: "/unused-checkpoint"), authorization: oldAuthorization
        ))
        let relaunched = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertFalse(relaunched.snapshot.isGranted)
        XCTAssertTrue(relaunched.requiresQueueReset)
    }

    func testWithdrawalRecapturesOrdinaryRevisionBeforeReturningWithDurableResetMarker() async throws {
        let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-withdrawal-revision-\(UUID().uuidString)"))
        let registeredURL = URL(fileURLWithPath: "/unused-revision-checkpoint")
        let cleanupEntered = DispatchSemaphore(value: 0)
        let releaseCleanup = DispatchSemaphore(value: 0)
        let registrationFinished = expectation(description: "concurrent diagnostic registration finished")
        let consent = IChartTelemetryConsentStore(defaults: defaults, removeDiagnosticFile: { url in
            guard url == registeredURL else { return }
            cleanupEntered.signal()
            if releaseCleanup.wait(timeout: .now() + 2) != .success {
                throw NSError(domain: "TelemetryCleanupTimeout", code: 1)
            }
        })
        consent.setConsentGranted(true)
        XCTAssertNotNil(consent.installationID(for: consent.snapshot))
        var injectedRevision = false
        defaults.onMutation = { key in
            guard key == "iChart.telemetry.queue-reset-required.v1", !injectedRevision else { return }
            injectedRevision = true
            DispatchQueue.global().async {
                consent.registerDiagnosticFile(registeredURL)
                registrationFinished.fulfill()
            }
            XCTAssertEqual(cleanupEntered.wait(timeout: .now() + 2), .success)
            releaseCleanup.signal()
            // This read waits for registration to release the state lock after
            // updating its revision; its preference projection is queued on main.
            _ = consent.snapshot
            defaults.removeObject(forKey: "iChart.telemetry.queue-reset-required.v1")
        }
        let withdrawAndCheckDurability = {
            consent.setConsentGranted(false)
            // Check on main before the queued registration projection can repair
            // the marker. Withdrawal itself must have persisted the new fields.
            XCTAssertTrue(defaults.bool(forKey: "iChart.telemetry.queue-reset-required.v1"))
            XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey))
            XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        }
        if Thread.isMainThread { withdrawAndCheckDurability() }
        else { DispatchQueue.main.sync(execute: withdrawAndCheckDurability) }
        defaults.onMutation = nil

        await fulfillment(of: [registrationFinished], timeout: 5)

        XCTAssertTrue(injectedRevision)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertTrue(consent.requiresQueueReset)
    }

    func testDirectWithdrawalInsidePreferenceCallbackRejectsConcurrentOldAuthorization() throws {
        let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-direct-withdrawal-admission-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        consent.setConsentGranted(true)
        let grant = consent.snapshot
        let authorization = try XCTUnwrap(consent.checkpointAuthorization())
        var didWithdraw = false
        defaults.onMutation = { _ in
            guard !didWithdraw else { return }
            didWithdraw = true
            defaults.removeObject(forKey: IChartTelemetryConsentStore.preferenceKey)
            let checked = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                XCTAssertNil(consent.performIfGranted(matching: grant) {
                    XCTFail("A preference projection must not admit old authorization after direct withdrawal")
                    return true
                })
                XCTAssertNil(consent.checkpointAuthorization())
                XCTAssertFalse((try? consent.publishDiagnosticCheckpoint(
                    Data([1]), to: URL(fileURLWithPath: "/unused-checkpoint"), authorization: authorization
                )) ?? true)
                checked.signal()
            }
            XCTAssertEqual(checked.wait(timeout: .now() + 2), .success)
        }

        XCTAssertTrue(consent.clearQueuedEvents(matching: grant) {})

        defaults.onMutation = nil
        XCTAssertTrue(didWithdraw)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertNil(consent.performIfGranted(matching: grant) { true })
    }

    func testRoutinePreferenceProjectionsCannotRestoreDirectPreferenceWithdrawal() throws {
        for projection in ["identity", "queue_reset", "diagnostic_cleanup"] {
            let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-direct-withdrawal-\(projection)-\(UUID().uuidString)"))
            let consent = IChartTelemetryConsentStore(defaults: defaults)
            consent.setConsentGranted(true)
            let grant = consent.snapshot
            let oldAuthorization = projection == "identity" ? nil : consent.checkpointAuthorization()
            var didWithdraw = false
            defaults.onMutation = { _ in
                XCTAssertTrue(Thread.isMainThread)
                guard !didWithdraw else { return }
                didWithdraw = true
                defaults.removeObject(forKey: IChartTelemetryConsentStore.preferenceKey)
            }

            switch projection {
            case "identity": _ = consent.installationID(for: grant)
            case "queue_reset": XCTAssertTrue(consent.clearQueuedEvents(matching: grant) {})
            default: consent.retryDiagnosticCleanup()
            }

            defaults.onMutation = nil
            XCTAssertTrue(didWithdraw, projection)
            XCTAssertFalse(consent.snapshot.isGranted, projection)
            XCTAssertTrue(consent.requiresQueueReset, projection)
            XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey), projection)
            XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey), projection)
            XCTAssertNil(consent.performIfGranted(matching: grant) { true }, projection)
            if let oldAuthorization {
                XCTAssertFalse(try consent.publishDiagnosticCheckpoint(
                    Data([1]), to: URL(fileURLWithPath: "/unused-checkpoint"), authorization: oldAuthorization
                ), projection)
            }
            let relaunched = IChartTelemetryConsentStore(defaults: defaults)
            XCTAssertFalse(relaunched.snapshot.isGranted, projection)
            XCTAssertTrue(relaunched.requiresQueueReset, projection)
        }
    }

    func testReentrantWithdrawalPreventsOlderGrantProjectionFromRestoringConsent() throws {
        let defaults = try XCTUnwrap(ReentrantTelemetryDefaults(suiteName: "iChart-consent-nested-transition-\(UUID().uuidString)"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        var didWithdraw = false
        defaults.onMutation = { _ in
            guard !didWithdraw else { return }
            didWithdraw = true
            consent.setConsentGranted(false)
        }

        consent.setConsentGranted(true)

        XCTAssertTrue(didWithdraw)
        XCTAssertFalse(consent.snapshot.isGranted)
        XCTAssertTrue(consent.requiresQueueReset)
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey))
        XCTAssertNil(defaults.string(forKey: IChartTelemetryConsentStore.installationIDPreferenceKey))
        let relaunched = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertFalse(relaunched.snapshot.isGranted)
        XCTAssertTrue(relaunched.requiresQueueReset)
        defaults.onMutation = nil
    }

    func testTelemetryPrivacyDropsUnknownContentLikeProperties() {
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "layout_style": .string("leadSheet"),
            "alteration_issue_count": .int(1),
            "barline_sequence_issue_count": .int(1),
            "duration_ms": .double(12.34567),
            "candidate_limit_issue_count": .int(1),
            "dim_quality_issue_count": .int(1),
            "extension_issue_count": .int(1),
            "rendered_ink_median_luminance": .double(0.06123),
            "stroke_color_median_luminance": .double(0.05999),
            "canvas_override_user_interface_style": .string("light"),
            "canvas_drawing_policy": .string("any_input"),
            "close_race_count": .int(1),
            "cluster_count": .int(4),
            "confirm_count": .int(2),
            "draft_count": .int(3),
            "generated_sequence_limit_count": .int(0),
            "matched_count": .int(2),
            "no_read_count": .int(1),
            "quality_issue_count": .int(1),
            "raw_candidate_count": .int(9),
            "recognition_pipeline_version": .string(ChordInkRecognitionPipelineIdentity.version),
            "recognition_target_count": .int(3),
            "review_candidate_count": .int(2),
            "root_accidental_issue_count": .int(1),
            "root_issue_count": .int(1),
            "slash_bass_issue_count": .int(1),
            "source_coordinate_width": .double(1366),
            "source_coordinate_height": .double(1024),
            "target_coordinate_width": .double(1024),
            "target_coordinate_height": .double(1366),
            "triangle_quality_issue_count": .int(1),
            "trust_corroborated_count": .int(2),
            "trust_outcome": .string("corroborated"),
            "trust_probe_count": .int(6),
            "trust_rejected_count": .int(1),
            "trust_symbol_support_count": .int(4),
            "trust_validation_ms": .double(8.12345),
            "trusted_count": .int(1),
            "unknown_issue_count": .int(0),
            "unresolved_count": .int(1),
            "live_canvas_light_trait_guard_enabled": .bool(true),
            "tool_ink_type": .string("pen"),
            "tool_is_inking": .bool(true),
            "tool_matches_persistent_ink": .bool(true),
            "tool_width": .double(3.4567),
            "user_signed_in": .bool(true),
            "chart_title": .string("Do Not Collect"),
            "raw_chord_text": .string("C7")
        ])

        XCTAssertEqual(sanitized["layout_style"], .string("leadSheet"))
        XCTAssertEqual(sanitized["alteration_issue_count"], .int(1))
        XCTAssertEqual(sanitized["barline_sequence_issue_count"], .int(1))
        XCTAssertEqual(sanitized["duration_ms"], .double(12.346))
        XCTAssertEqual(sanitized["candidate_limit_issue_count"], .int(1))
        XCTAssertEqual(sanitized["dim_quality_issue_count"], .int(1))
        XCTAssertEqual(sanitized["extension_issue_count"], .int(1))
        XCTAssertEqual(sanitized["rendered_ink_median_luminance"], .double(0.061))
        XCTAssertEqual(sanitized["stroke_color_median_luminance"], .double(0.06))
        XCTAssertEqual(sanitized["canvas_override_user_interface_style"], .string("light"))
        XCTAssertEqual(sanitized["canvas_drawing_policy"], .string("any_input"))
        XCTAssertEqual(sanitized["close_race_count"], .int(1))
        XCTAssertEqual(sanitized["cluster_count"], .int(4))
        XCTAssertEqual(sanitized["confirm_count"], .int(2))
        XCTAssertEqual(sanitized["draft_count"], .int(3))
        XCTAssertEqual(sanitized["generated_sequence_limit_count"], .int(0))
        XCTAssertEqual(sanitized["matched_count"], .int(2))
        XCTAssertEqual(sanitized["no_read_count"], .int(1))
        XCTAssertEqual(sanitized["quality_issue_count"], .int(1))
        XCTAssertEqual(sanitized["raw_candidate_count"], .int(9))
        XCTAssertEqual(
            sanitized["recognition_pipeline_version"],
            .string(ChordInkRecognitionPipelineIdentity.version)
        )
        XCTAssertEqual(sanitized["recognition_target_count"], .int(3))
        XCTAssertEqual(sanitized["review_candidate_count"], .int(2))
        XCTAssertEqual(sanitized["root_accidental_issue_count"], .int(1))
        XCTAssertEqual(sanitized["root_issue_count"], .int(1))
        XCTAssertEqual(sanitized["slash_bass_issue_count"], .int(1))
        XCTAssertEqual(sanitized["source_coordinate_width"], .double(1366))
        XCTAssertEqual(sanitized["source_coordinate_height"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_width"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_height"], .double(1366))
        XCTAssertEqual(sanitized["triangle_quality_issue_count"], .int(1))
        XCTAssertEqual(sanitized["trust_corroborated_count"], .int(2))
        XCTAssertEqual(sanitized["trust_outcome"], .string("corroborated"))
        XCTAssertEqual(sanitized["trust_probe_count"], .int(6))
        XCTAssertEqual(sanitized["trust_rejected_count"], .int(1))
        XCTAssertEqual(sanitized["trust_symbol_support_count"], .int(4))
        XCTAssertEqual(sanitized["trust_validation_ms"], .double(8.123))
        XCTAssertEqual(sanitized["trusted_count"], .int(1))
        XCTAssertEqual(sanitized["unknown_issue_count"], .int(0))
        XCTAssertEqual(sanitized["unresolved_count"], .int(1))
        XCTAssertEqual(sanitized["live_canvas_light_trait_guard_enabled"], .bool(true))
        XCTAssertEqual(sanitized["tool_ink_type"], .string("pen"))
        XCTAssertEqual(sanitized["tool_is_inking"], .bool(true))
        XCTAssertEqual(sanitized["tool_matches_persistent_ink"], .bool(true))
        XCTAssertEqual(sanitized["tool_width"], .double(3.457))
        XCTAssertEqual(sanitized["user_signed_in"], .bool(true))
        XCTAssertNil(sanitized["chart_title"])
        XCTAssertNil(sanitized["raw_chord_text"])
    }

    func testTelemetryQueuePersistsAndRemovesEventsByClientID() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let queueURL = directory.appendingPathComponent("telemetry-queue.json")
        let queue = IChartTelemetryQueueStore(url: queueURL, maxEventCount: 10)

        let firstEvent = event(named: "app.launched")
        let secondEvent = event(named: "pdf.export_succeeded")
        try queue.append(firstEvent)
        try queue.append(secondEvent)

        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [
            firstEvent.clientEventID,
            secondEvent.clientEventID
        ])

        try queue.removeEvents(withIDs: [firstEvent.clientEventID])
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), [secondEvent.clientEventID])
    }

    func testLiveTelemetryIsDisabledDuringXCTest() {
        let configuration = IChartSupabaseConfiguration(
            url: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-test-key"
        )

        XCTAssertFalse(IChartTelemetryService.allowsLiveTelemetry(environment: [
            "XCTestConfigurationFilePath": "/tmp/iChart.xctestconfiguration"
        ]))
        XCTAssertNil(IChartTelemetryService.live(
            clients: nil,
            configuration: configuration,
            environment: [
                "XCTestConfigurationFilePath": "/tmp/iChart.xctestconfiguration"
            ]
        ))
    }

    func testLiveTelemetryCanStartOutsideXCTestWhenConfigured() {
        let configuration = IChartSupabaseConfiguration(
            url: URL(string: "https://example.supabase.co")!,
            publishableKey: "publishable-test-key"
        )

        XCTAssertTrue(IChartTelemetryService.allowsLiveTelemetry(environment: [:]))
        XCTAssertNotNil(IChartTelemetryService.live(
            clients: nil,
            configuration: configuration,
            environment: [:]
        ))
    }

    func testTelemetryAllowsContentFreeRenderedChordCorrectionFeedback() {
        XCTAssertTrue(
            IChartTelemetryPrivacy.allowedEventNames.contains("chord.rendered_correction_applied")
        )

        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "candidate_count": .int(3),
            "decision": .string("candidate_replacement"),
            "layout_style": .string("simpleChordSheet"),
            "result": .string("memory_updated"),
            "source": .string("recognized_ink"),
            "previous_chord_text": .string("C"),
            "accepted_chord_text": .string("G")
        ])

        XCTAssertEqual(sanitized["candidate_count"], .int(3))
        XCTAssertEqual(sanitized["decision"], .string("candidate_replacement"))
        XCTAssertEqual(sanitized["result"], .string("memory_updated"))
        XCTAssertEqual(sanitized["source"], .string("recognized_ink"))
        XCTAssertNil(sanitized["previous_chord_text"])
        XCTAssertNil(sanitized["accepted_chord_text"])
    }

    func testFeatureContractPropertiesHaveNarrowTypesWithoutChangingLegacyReasons() {
        let operationID = UUID().uuidString
        let valid = IChartTelemetryPrivacy.sanitizedProperties([
            "contract_id": .string("ink.render_preservation"),
            "contract_version": .int(1),
            "operation_id": .string(operationID),
            "operation": .string("render"),
            "outcome": .string("violated"),
            "reason": .string("render_source_missing"),
            "scope": .string("chords"),
            "expected_count": .int(4),
            "actual_count": .int(3),
            "expected_bytes": .int(10_000),
            "actual_bytes": .int(9_000),
            "content_matches": .bool(false),
            "build_source": .string("release_build"),
            "chart_reference": .string(String(repeating: "a", count: 64)),
            "error_code": .string("must not ride along"),
            "drawing_data": .string("must not upload")
        ], forEventName: "feature.contract_checked")
        XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(valid))
        XCTAssertEqual(valid["operation_id"], .string(operationID.lowercased()))
        XCTAssertEqual(valid["expected_count"], .int(4))
        XCTAssertEqual(valid["content_matches"], .bool(false))
        XCTAssertNil(valid["error_code"])
        XCTAssertNil(valid["drawing_data"])

        let invalid = IChartTelemetryPrivacy.sanitizedProperties([
            "contract_id": .string("arbitrary chart text"),
            "contract_version": .int(2),
            "operation_id": .string("arbitrary chart text"),
            "outcome": .string("arbitrary chart text"),
            "reason": .string("arbitrary chart text"),
            "scope": .string("arbitrary chart text"),
            "expected_count": .string("arbitrary chart text"),
            "actual_count": .int(-1),
            "expected_bytes": .int(1_000_000_000_001),
            "content_matches": .string("false"),
            "chart_reference": .string(UUID().uuidString),
            "duration_ms": .double(.infinity)
        ], forEventName: "feature.contract_checked")
        XCTAssertTrue(invalid.isEmpty)
        XCTAssertFalse(IChartTelemetryPrivacy.hasRequiredContractFields(invalid))
        XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties([
            "reason": .string("existing reason value"), "scope": .string("existing scope value")
        ])["reason"], .string("existing reason value"))
    }

    func testAutomaticRenderEnvelopeAllowsOnlyBoundedTechnicalFields() {
        let base: IChartTelemetryProperties = [
            "contract_id": .string("ink.automatic_render_completion"), "contract_version": .int(1),
            "operation_id": .string(UUID().uuidString), "operation": .string("render"),
            "outcome": .string("protected_rejection"), "reason": .string("automatic_no_read"),
            "build_source": .string("debug_build"), "render_mode": .string("automatic"),
            "source_stroke_count": .int(7), "consumed_stroke_count": .int(4),
            "retained_stroke_count": .int(3), "actual_count": .int(3), "duration_ms": .double(3_001)
        ]
        let clean = IChartTelemetryPrivacy.sanitizedProperties(base.merging([
            "raw_chord_text": .string("PRIVATE"), "drawing_data": .string("PRIVATE"),
            "severity": .string("critical")
        ]) { _, right in right }, forEventName: "feature.contract_checked")
        XCTAssertTrue(IChartTelemetryPrivacy.hasRequiredContractFields(clean))
        XCTAssertEqual(clean["render_mode"], .string("automatic"))
        XCTAssertEqual(clean["source_stroke_count"], .int(7))
        XCTAssertEqual(clean["consumed_stroke_count"], .int(4))
        XCTAssertEqual(clean["retained_stroke_count"], .int(3))
        XCTAssertNil(clean["raw_chord_text"])
        XCTAssertNil(clean["drawing_data"])
        XCTAssertNil(clean["severity"])
        for key in ["source_stroke_count", "consumed_stroke_count", "retained_stroke_count"] {
            for invalid in [IChartTelemetryValue.string("PRIVATE"), .int(-1), .double(.infinity)] {
                var changed = base; changed[key] = invalid
                XCTAssertNil(IChartTelemetryPrivacy.sanitizedProperties(changed,
                    forEventName: "feature.contract_checked")[key])
            }
        }
        var changed = base; changed["render_mode"] = .string("PRIVATE")
        XCTAssertNil(IChartTelemetryPrivacy.sanitizedProperties(changed,
            forEventName: "feature.contract_checked")["render_mode"])
    }

    func testTelemetryQueueMigratesLegacyArrayAndAccountsForOverflowAtomically() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let queueURL = directory.appendingPathComponent("queue.json")
        let inputs = (0..<3).map { _ in event(named: "app.launched") }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Array(inputs.prefix(2))).write(to: queueURL, options: .atomic)
        let queue = IChartTelemetryQueueStore(url: queueURL, maxEventCount: 2)
        XCTAssertEqual(try queue.loadEvents().map(\.clientEventID), Array(inputs.prefix(2)).map(\.clientEventID))
        try queue.append(inputs[2])
        let recreated = IChartTelemetryQueueStore(url: queueURL, maxEventCount: 2)
        XCTAssertEqual(try recreated.loadEvents().map(\.clientEventID), Array(inputs.suffix(2)).map(\.clientEventID))
        XCTAssertEqual(try recreated.healthSnapshot().overflowDroppedEventCount, 1)
        try recreated.acknowledge(acceptedIDs: [inputs[1].clientEventID], rejectedIDs: [inputs[2].clientEventID])
        XCTAssertTrue(try recreated.loadEvents().isEmpty)
        XCTAssertEqual(try recreated.loadQuarantinedEvents().map(\.clientEventID), [inputs[2].clientEventID])
        XCTAssertEqual(try recreated.healthSnapshot().serverRejectedEventCount, 1)
        try recreated.acknowledge(acceptedIDs: [], rejectedIDs: [inputs[2].clientEventID])
        XCTAssertEqual(try recreated.healthSnapshot().serverRejectedEventCount, 1)
        try recreated.clear()
        XCTAssertTrue(try recreated.loadQuarantinedEvents().isEmpty)
        XCTAssertEqual(try recreated.healthSnapshot().overflowDroppedEventCount, 0)
        XCTAssertEqual(try recreated.healthSnapshot().serverRejectedEventCount, 0)
    }

    func testTelemetryAcknowledgmentDoesNotTreatBooleanOrMissingCountsAsFullSuccess() throws {
        let id = UUID()
        for payload in [
            "{\"accepted\":true}",
            "{\"accepted\":1,\"stored_count\":1,\"rejected_count\":0}",
            "{\"accepted\":true,\"stored_count\":true,\"rejected_count\":0}",
            "{\"accepted\":true,\"stored_count\":1,\"rejected_count\":1}"
        ] {
            XCTAssertNil(IChartTelemetryAcknowledgment.parse(Data(payload.utf8), sentIDs: [id]))
        }
        let complete = IChartTelemetryAcknowledgment.parse(
            Data("{\"accepted\":true,\"stored_count\":1,\"rejected_count\":0}".utf8),
            sentIDs: [id]
        )
        XCTAssertEqual(complete?.acceptedIDs, [id])
    }

    func testQueueHealthMetadataAcceptsOnlyBoundedIntegerTotals() {
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "queue_overflow_count": .int(12),
            "queue_rejected_count": .string("do not upload"),
            "queue_quarantine_overflow_count": .int(-1),
            "queue_unacknowledged_batch_count": .int(1_000_000_000_001)
        ])
        XCTAssertEqual(sanitized, ["queue_overflow_count": .int(12)])
    }

    private func event(named name: String) -> IChartTelemetryEvent {
        IChartTelemetryEvent(
            clientEventID: UUID(),
            eventName: name,
            occurredAt: Date(timeIntervalSince1970: 1_786_649_400),
            installationID: UUID(),
            sessionID: UUID(),
            appVersion: "1.1.2",
            buildNumber: "42",
            platform: "iPadOS",
            osVersion: "26.6",
            deviceModel: "iPad14,3",
            localeLanguage: "en-US",
            timeZoneOffsetMinutes: -420,
            properties: ["result": .string("ok")]
        )
    }
}
private final class TelemetryStartupCleanupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var didBlock = false
    private let entered = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func enable() {
        lock.lock()
        enabled = true
        lock.unlock()
    }

    func blockWhenEnabled() throws {
        lock.lock()
        let shouldBlock = enabled && !didBlock
        if shouldBlock { didBlock = true }
        lock.unlock()
        guard shouldBlock else { return }
        entered.signal()
        if released.wait(timeout: .now() + 5) != .success {
            throw NSError(domain: "TelemetryStartupCleanupTimeout", code: 1)
        }
    }

    func waitUntilEntered() -> Bool { entered.wait(timeout: .now() + 5) == .success }
    func release() { released.signal() }
}

private final class TelemetryPreferenceCallbackState: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var timedOut = false

    func beginCallback() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !entered else { return false }
        entered = true
        return true
    }

    func recordTimeout() {
        lock.lock()
        timedOut = true
        lock.unlock()
    }

    var didReenter: Bool {
        lock.lock()
        defer { lock.unlock() }
        return entered
    }

    var didTimeout: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timedOut
    }
}

/// Models UserDefaults' synchronous notifications. Reentering a consent read
/// here deadlocks if preference access holds the authoritative state lock.
private final class ReentrantTelemetryDefaults: UserDefaults, @unchecked Sendable {
    var onMutation: ((String) -> Void)?
    private var mutationDepth = 0

    override func set(_ value: Any?, forKey defaultName: String) {
        mutationDepth += 1
        defer { mutationDepth -= 1 }
        super.set(value, forKey: defaultName)
        if mutationDepth == 1 { onMutation?(defaultName) }
    }

    override func removeObject(forKey defaultName: String) {
        mutationDepth += 1
        defer { mutationDepth -= 1 }
        super.removeObject(forKey: defaultName)
        if mutationDepth == 1 { onMutation?(defaultName) }
    }
}

#endif

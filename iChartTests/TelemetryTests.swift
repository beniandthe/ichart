#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class TelemetryTests: XCTestCase {
    @MainActor
    func testConsentDefaultsOffAndExplicitSelectionInvalidatesOldGenerations() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-consent-\(UUID())"))
        let consent = IChartTelemetryConsentStore(defaults: defaults)
        XCTAssertFalse(consent.snapshot.isGranted)
        consent.setConsentGranted(true)
        let original = consent.cachedSnapshotForScheduling
        XCTAssertTrue(original.isGranted)
        await consent.waitForPendingPersistence()
        consent.setConsentGranted(false)
        XCTAssertFalse(consent.trySnapshotForScheduling()?.isGranted ?? true)
        consent.setConsentGranted(true)
        let replacement = consent.cachedSnapshotForScheduling
        XCTAssertNotEqual(replacement, original)
        XCTAssertNil(consent.performIfGranted(matching: original) { true })
        await consent.waitForPendingPersistence()
        XCTAssertTrue(consent.snapshot.isGranted)
        XCTAssertEqual(defaults.string(forKey: IChartTelemetryConsentStore.preferenceKey), IChartTelemetryConsentStore.currentVersion)
        XCTAssertTrue(consent.requiresQueueReset)
    }

    func testUnknownAndLegacyConsentValuesRemainDisabled() throws {
        for version in ["true", "telemetry-consent-v0", "telemetry-consent-v2"] {
            let defaults = try XCTUnwrap(UserDefaults(suiteName: "basic-old-consent-\(UUID())"))
            defaults.set(version, forKey: IChartTelemetryConsentStore.preferenceKey)
            let consent = IChartTelemetryConsentStore(defaults: defaults)
            XCTAssertFalse(consent.snapshot.isGranted)
            XCTAssertNil(consent.installationID(for: consent.snapshot))
        }
    }

    func testBasicPolicyDropsContentAndMapsUnboundedErrorTextToUnknown() {
        let values = IChartTelemetryPrivacy.sanitizedProperties([
            "error_code": .string("a private exception and chart title"),
            "operation": .string("library_save"), "duration_ms": .double(12.12567),
            "chart_reference": .string(String(repeating: "a", count: 64)),
            "source": .string("private source"), "flow": .string("private flow"),
            "stroke_count": .int(99), "canvas_alpha": .double(0),
            "recognition_pipeline_version": .string("private pipeline"),
            "auth_state": .string("signed_in"), "raw_chord_text": .string("fixture chord")
        ], forEventName: "app.error")
        XCTAssertEqual(values, ["error_code": .string("unknown"), "source": .string("library_save"),
                                "duration_ms": .double(12.126)])
        for code in ["library_load_failed", "library_save_failed", "unsupported_candidate", "missing_measure"] {
            XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties(["error_code": .string(code)],
                forEventName: "app.error")["error_code"], .string(code))
        }
    }

    func testFixedOperationUsesTheExistingSourceWireKeyAndSanitizationIsIdempotent() {
        for operation in ["library_load", "library_save", "recognize", "render", "export", "backup", "restore"] {
            let input: IChartTelemetryProperties = ["operation": .string(operation), "error_code": .string("save_error")]
            let wire = IChartTelemetryPrivacy.sanitizedProperties(input, forEventName: "app.error")
            XCTAssertEqual(wire, ["source": .string(operation), "error_code": .string("save_error")])
            XCTAssertNil(wire["operation"])
            XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties(wire, forEventName: "app.error"), wire)
        }
        XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties([
            "operation": .string("library_save"), "source": .string("export")
        ], forEventName: "app.error"), ["source": .string("library_save")])
        for field in ["operation", "source"] {
            for value in [IChartTelemetryValue.string("PRIVATE_ARBITRARY_SOURCE"), .int(7)] {
                let values = IChartTelemetryPrivacy.sanitizedProperties([field: value], forEventName: "app.error")
                XCTAssertNil(values["source"])
                XCTAssertNil(values["operation"])
            }
        }
    }

    func testCountersAndTimingsRejectStringsNegativeAndNonfiniteValues() {
        let values = IChartTelemetryPrivacy.sanitizedProperties([
            "duration_ms": .double(.infinity), "recognition_ms": .double(-1),
            "candidate_count": .string("private text"), "rendered_count": .int(-1),
            "queue_rejected_count": .int(1_000_000_001)
        ], forEventName: "chord.preview_rendered")
        XCTAssertTrue(values.isEmpty)
        XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties([
            "candidate_count": .int(3), "recognition_ms": .double(3000.123456789)
        ], forEventName: "chord.preview_rendered"), ["candidate_count": .int(3), "recognition_ms": .double(3000.123)])
    }

    func testRenderedCorrectionsRetainOnlyFixedDecisionsAndCounts() {
        for decision in ["outside_candidates", "candidate_replacement", "equivalent_spelling", "display_space_mismatch"] {
            XCTAssertEqual(IChartTelemetryPrivacy.sanitizedProperties([
                "decision": .string(decision), "candidate_count": .int(3),
                "previous_text": .string("fixture"), "accepted_text": .string("fixture")
            ], forEventName: "chord.rendered_correction_applied"),
                ["decision": .string(decision), "candidate_count": .int(3)])
        }
        XCTAssertTrue(IChartTelemetryPrivacy.sanitizedProperties(["decision": .string("private text")],
            forEventName: "chord.rendered_correction_applied").isEmpty)
    }

    func testLiveInkAndFeatureContractsAreRejectedByEventPolicy() {
        for name in ["feature.contract_checked", "ink.persisted", "ink.visibility_probe", "chord.preview_updated",
                     "editor.opened", "auth.state_changed", "subscription.entitlement_changed"] {
            XCTAssertFalse(IChartTelemetryPrivacy.allowedEventNames.contains(name))
            XCTAssertTrue(IChartTelemetryPrivacy.sanitizedProperties(["duration_ms": .int(12)], forEventName: name).isEmpty)
        }
        XCTAssertFalse(IChartTelemetryPrivacy.hasRequiredContractFields([:]))
        XCTAssertFalse(IChartTelemetry.isRecordingEnabled)
        XCTAssertNil(IChartTelemetry.diagnosticAuthorization())
    }

    func testQueueMigratesLegacyArrayAndFiltersRichEventsBeforeUpload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("basic-queue-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let error = basicFixtureEvent(properties: ["error_code": .string("save_error"),
            "operation": .string("library_save"), "raw_chord_text": .string("fixture")])
        let retired = basicFixtureEvent(name: "feature.contract_checked")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([error, retired]).write(to: url)
        let queue = IChartTelemetryQueueStore(url: url)
        try queue.retainBasicEvents()
        let remaining = try XCTUnwrap(queue.loadEvents().first)
        XCTAssertEqual(try queue.loadEvents().count, 1)
        XCTAssertEqual(remaining.clientEventID, error.clientEventID)
        XCTAssertEqual(remaining.properties, ["error_code": .string("save_error"), "source": .string("library_save")])
        XCTAssertEqual(remaining.platform, "iOS")
        XCTAssertEqual(remaining.deviceModel, "iOS device")
        XCTAssertEqual(remaining.localeLanguage, "unknown")
    }

    func testOversizedQueueFailsClosedWithoutUnboundedFileRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("basic-large-queue-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 32, count: 512_001).write(to: url)
        XCTAssertThrowsError(try IChartTelemetryQueueStore(url: url).loadEvents())
    }
}

func basicFixtureEvent(name: String = "app.error", properties: IChartTelemetryProperties = [:]) -> IChartTelemetryEvent {
    .init(clientEventID: UUID(), eventName: name, occurredAt: Date(timeIntervalSince1970: 1_800_000_000),
          installationID: UUID(), sessionID: UUID(), appVersion: "1.2.4", buildNumber: "0", platform: "iPadOS",
          osVersion: "26", deviceModel: "old-hardware-name", localeLanguage: "en", timeZoneOffsetMinutes: 0,
          properties: properties)
}
#endif

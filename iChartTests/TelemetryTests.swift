import XCTest

#if canImport(UIKit)
@testable import iChart

final class TelemetryTests: XCTestCase {
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
            "recognition_target_count": .int(3),
            "root_accidental_issue_count": .int(1),
            "root_issue_count": .int(1),
            "slash_bass_issue_count": .int(1),
            "source_coordinate_width": .double(1366),
            "source_coordinate_height": .double(1024),
            "target_coordinate_width": .double(1024),
            "target_coordinate_height": .double(1366),
            "triangle_quality_issue_count": .int(1),
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
        XCTAssertEqual(sanitized["recognition_target_count"], .int(3))
        XCTAssertEqual(sanitized["root_accidental_issue_count"], .int(1))
        XCTAssertEqual(sanitized["root_issue_count"], .int(1))
        XCTAssertEqual(sanitized["slash_bass_issue_count"], .int(1))
        XCTAssertEqual(sanitized["source_coordinate_width"], .double(1366))
        XCTAssertEqual(sanitized["source_coordinate_height"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_width"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_height"], .double(1366))
        XCTAssertEqual(sanitized["triangle_quality_issue_count"], .int(1))
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
#endif

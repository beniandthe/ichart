import XCTest

#if canImport(UIKit)
@testable import iChart

final class TelemetryTests: XCTestCase {
    func testTelemetryPrivacyDropsUnknownContentLikeProperties() {
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "layout_style": .string("leadSheet"),
            "duration_ms": .double(12.34567),
            "rendered_ink_median_luminance": .double(0.06123),
            "stroke_color_median_luminance": .double(0.05999),
            "canvas_override_user_interface_style": .string("light"),
            "canvas_drawing_policy": .string("any_input"),
            "source_coordinate_width": .double(1366),
            "source_coordinate_height": .double(1024),
            "target_coordinate_width": .double(1024),
            "target_coordinate_height": .double(1366),
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
        XCTAssertEqual(sanitized["duration_ms"], .double(12.346))
        XCTAssertEqual(sanitized["rendered_ink_median_luminance"], .double(0.061))
        XCTAssertEqual(sanitized["stroke_color_median_luminance"], .double(0.06))
        XCTAssertEqual(sanitized["canvas_override_user_interface_style"], .string("light"))
        XCTAssertEqual(sanitized["canvas_drawing_policy"], .string("any_input"))
        XCTAssertEqual(sanitized["source_coordinate_width"], .double(1366))
        XCTAssertEqual(sanitized["source_coordinate_height"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_width"], .double(1024))
        XCTAssertEqual(sanitized["target_coordinate_height"], .double(1366))
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

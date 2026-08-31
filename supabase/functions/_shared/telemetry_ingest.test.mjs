import assert from "node:assert/strict";
import test from "node:test";

import {
  createTelemetryIngestDependencies,
  handleTelemetryIngestRequest,
  sanitizedProperties,
  telemetryRowFromEvent,
} from "./telemetry_ingest.mjs";

const validContext = {
  installation_id: "00000000-0000-4000-8000-000000000101",
  session_id: "00000000-0000-4000-8000-000000000202",
  app_version: "1.1.2",
  build_number: "42",
  platform: "iPadOS",
  os_version: "26.6",
  device_model: "iPad14,3",
  locale_language: "en-US",
  time_zone_offset_minutes: -420,
};

function validEvent(overrides = {}) {
  return {
    client_event_id: "00000000-0000-4000-8000-000000000303",
    event_name: "ink.visibility_probe",
    occurred_at: "2026-08-13T19:30:00.000Z",
    properties: {
      scope: "freehand",
      stroke_count: 2,
      point_count: 64,
      min_opacity: 1,
      median_opacity: 1,
      max_opacity: 1,
      light_stroke_count: 0,
      stroke_color_min_luminance: 0.06,
      stroke_color_median_luminance: 0.06,
      stroke_color_max_luminance: 0.06,
      tool_ink_type: "pen",
      tool_color_luminance: 0.06,
      tool_is_inking: true,
      tool_matches_persistent_ink: true,
      tool_width: 2.5,
      canvas_alpha: 1,
      canvas_user_interface_style: "light",
      canvas_override_user_interface_style: "light",
      canvas_superview_user_interface_style: "dark",
      canvas_window_user_interface_style: "dark",
      canvas_drawing_policy: "pencil_only",
      canvas_background_alpha: 0,
      canvas_is_opaque: false,
      canvas_is_hidden: false,
      canvas_user_interaction_enabled: true,
      canvas_is_first_responder: false,
      canvas_content_scale: 2,
      canvas_bounds_width: 1024,
      canvas_bounds_height: 768,
      live_canvas_light_trait_guard_enabled: true,
      rendered_ink_median_luminance: 0.06,
      rendered_ink_light_pixel_ratio: 0,
      rendered_ink_sample_count: 112,
      has_mask: false,
      normalization_needed: true,
      normalized_before_save: true,
      chart_title: "should never pass through",
      raw_chord_text: "C7",
    },
    ...overrides,
  };
}

test("telemetry row sanitizes event context and allowlisted properties", () => {
  const row = telemetryRowFromEvent(
    validEvent({
      properties: {
        ...validEvent().properties,
        duration_ms: 10.12345,
        error_message: "not allowed",
      },
    }),
    validContext,
    "00000000-0000-4000-8000-000000000404"
  );

  assert.equal(row.event_name, "ink.visibility_probe");
  assert.equal(row.owner_id, "00000000-0000-4000-8000-000000000404");
  assert.equal(row.installation_id, validContext.installation_id);
  assert.equal(row.app_version, "1.1.2");
  assert.equal(row.properties.scope, "freehand");
  assert.equal(row.properties.duration_ms, 10.123);
  assert.equal(row.properties.tool_ink_type, "pen");
  assert.equal(row.properties.tool_matches_persistent_ink, true);
  assert.equal(row.properties.tool_width, 2.5);
  assert.equal(row.properties.canvas_override_user_interface_style, "light");
  assert.equal(row.properties.canvas_superview_user_interface_style, "dark");
  assert.equal(row.properties.canvas_window_user_interface_style, "dark");
  assert.equal(row.properties.canvas_drawing_policy, "pencil_only");
  assert.equal(row.properties.canvas_user_interaction_enabled, true);
  assert.equal(row.properties.live_canvas_light_trait_guard_enabled, true);
  assert.equal(row.properties.rendered_ink_sample_count, 112);
  assert.equal(row.properties.canvas_is_opaque, false);
  assert.equal(row.properties.raw_chord_text, undefined);
  assert.equal(row.properties.chart_title, undefined);
  assert.equal(row.properties.error_message, undefined);
});

test("telemetry row allows coordinate reprojection diagnostics", () => {
  const row = telemetryRowFromEvent(
    validEvent({
      event_name: "ink.coordinate_space_reprojected",
      properties: {
        scope: "freehand",
        stroke_count: 2,
        source_coordinate_width: 1366,
        source_coordinate_height: 1024,
        target_coordinate_width: 1024,
        target_coordinate_height: 1366,
        canvas_bounds_width: 1024,
        canvas_bounds_height: 1366,
        chart_title: "should never pass through",
      },
    }),
    validContext
  );

  assert.ok(row);
  assert.equal(row.event_name, "ink.coordinate_space_reprojected");
  assert.equal(row.properties.scope, "freehand");
  assert.equal(row.properties.stroke_count, 2);
  assert.equal(row.properties.source_coordinate_width, 1366);
  assert.equal(row.properties.source_coordinate_height, 1024);
  assert.equal(row.properties.target_coordinate_width, 1024);
  assert.equal(row.properties.target_coordinate_height, 1366);
  assert.equal(row.properties.canvas_bounds_width, 1024);
  assert.equal(row.properties.canvas_bounds_height, 1366);
  assert.equal(row.properties.chart_title, undefined);
});

test("telemetry row rejects unknown event names and malformed ids", () => {
  assert.equal(
    telemetryRowFromEvent(validEvent({ event_name: "chart.content_uploaded" }), validContext),
    null
  );
  assert.equal(
    telemetryRowFromEvent(validEvent({ client_event_id: "not-a-uuid" }), validContext),
    null
  );
});

test("sanitized properties drops arrays and objects", () => {
  assert.deepEqual(
    sanitizedProperties({
      result: "ok",
      chart_count: 3,
      user_signed_in: true,
      source: ["not", "allowed"],
      reason: { nested: "nope" },
    }),
    {
      chart_count: 3,
      result: "ok",
      user_signed_in: true,
    }
  );
});

test("telemetry row allows aggregate chord preview handwriting quality without content", () => {
  const row = telemetryRowFromEvent(
    validEvent({
      event_name: "chord.preview_updated",
      properties: {
        barline_count: 0,
        batch_size: 4,
        candidate_count: 12,
        close_race_count: 1,
        cluster_count: 7,
        confidence_bucket: "3_4",
        confirm_count: 1,
        decision: "mixed",
        draft_count: 4,
        flow: "draft_preview",
        generated_sequence_limit_count: 0,
        layout_style: "simpleChordSheet",
        matched_count: 3,
        no_read_count: 1,
        raw_candidate_count: 18,
        recognition_ms: 14.12567,
        recognition_target_count: 4,
        result: "partial",
        stroke_count: 13,
        trusted_count: 3,
        unresolved_count: 1,
        raw_chord_text: "D/F#",
        drawing_payload: "not allowed",
      },
    }),
    validContext
  );

  assert.ok(row);
  assert.equal(row.event_name, "chord.preview_updated");
  assert.equal(row.properties.barline_count, 0);
  assert.equal(row.properties.batch_size, 4);
  assert.equal(row.properties.candidate_count, 12);
  assert.equal(row.properties.close_race_count, 1);
  assert.equal(row.properties.cluster_count, 7);
  assert.equal(row.properties.confidence_bucket, "3_4");
  assert.equal(row.properties.confirm_count, 1);
  assert.equal(row.properties.decision, "mixed");
  assert.equal(row.properties.draft_count, 4);
  assert.equal(row.properties.flow, "draft_preview");
  assert.equal(row.properties.generated_sequence_limit_count, 0);
  assert.equal(row.properties.layout_style, "simpleChordSheet");
  assert.equal(row.properties.matched_count, 3);
  assert.equal(row.properties.no_read_count, 1);
  assert.equal(row.properties.raw_candidate_count, 18);
  assert.equal(row.properties.recognition_ms, 14.126);
  assert.equal(row.properties.recognition_target_count, 4);
  assert.equal(row.properties.result, "partial");
  assert.equal(row.properties.stroke_count, 13);
  assert.equal(row.properties.trusted_count, 3);
  assert.equal(row.properties.unresolved_count, 1);
  assert.equal(row.properties.raw_chord_text, undefined);
  assert.equal(row.properties.drawing_payload, undefined);
});

test("telemetry row accepts chord preview render lifecycle events", () => {
  for (const eventName of [
    "chord.preview_rendered",
    "chord.preview_discarded",
    "chord.draft_barline_added",
  ]) {
    const row = telemetryRowFromEvent(
      validEvent({
        event_name: eventName,
        properties: {
          draft_count: 2,
          barline_count: 1,
          rendered_count: 2,
          unresolved_count: 0,
        },
      }),
      validContext
    );

    assert.ok(row);
    assert.equal(row.event_name, eventName);
    assert.equal(row.properties.draft_count, 2);
    assert.equal(row.properties.barline_count, 1);
    assert.equal(row.properties.unresolved_count, 0);
  }
});

test("ingest stores valid signed-out telemetry batches", async () => {
  let storedRows = null;
  const response = await handleTelemetryIngestRequest(
    new Request("https://example.test/functions/v1/app-telemetry-ingest", {
      method: "POST",
      body: JSON.stringify({
        context: validContext,
        events: [validEvent()],
      }),
    }),
    {
      authenticatedUserID: async () => null,
      insertTelemetryEvents: async (rows) => {
        storedRows = rows;
      },
    }
  );

  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.stored_count, 1);
  assert.equal(body.rejected_count, 0);
  assert.equal(storedRows.length, 1);
  assert.equal(storedRows[0].owner_id, null);
});

test("ingest rejects invalid client api keys when configured", async () => {
  let didFetch = false;
  const dependencies = createTelemetryIngestDependencies({
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-key",
    SUPABASE_ANON_KEY: "client-key",
  }, {
    fetch: async () => {
      didFetch = true;
      throw new Error("should not call Supabase");
    },
  });

  const response = await handleTelemetryIngestRequest(
    new Request("https://example.test/functions/v1/app-telemetry-ingest", {
      method: "POST",
      headers: { apikey: "wrong-key" },
      body: JSON.stringify({
        context: validContext,
        events: [validEvent()],
      }),
    }),
    dependencies
  );

  assert.equal(response.status, 401);
  assert.equal(didFetch, false);
});

test("ingest accepts signed-out telemetry with the configured client key", async () => {
  let storedRows = null;
  const dependencies = createTelemetryIngestDependencies({
    SUPABASE_URL: "https://project.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "server-only-key",
    SUPABASE_ANON_KEY: "client-key",
  }, {
    fetch: async (url, request) => {
      assert.equal(
        String(url),
        "https://project.supabase.co/rest/v1/telemetry_events?on_conflict=client_event_id"
      );
      assert.equal(request.headers.apikey, "server-only-key");
      assert.equal(request.headers.prefer, "resolution=ignore-duplicates,return=minimal");
      storedRows = JSON.parse(request.body);
      return new Response("", { status: 201 });
    },
  });

  const response = await handleTelemetryIngestRequest(
    new Request("https://example.test/functions/v1/app-telemetry-ingest", {
      method: "POST",
      headers: { apikey: "client-key" },
      body: JSON.stringify({
        context: validContext,
        events: [validEvent()],
      }),
    }),
    dependencies
  );

  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.stored_count, 1);
  assert.equal(storedRows.length, 1);
  assert.equal(storedRows[0].owner_id, null);
});

test("ingest attaches owner id when bearer session resolves", async () => {
  let storedRows = null;
  const response = await handleTelemetryIngestRequest(
    new Request("https://example.test/functions/v1/app-telemetry-ingest", {
      method: "POST",
      headers: { authorization: "Bearer user-token" },
      body: JSON.stringify({
        context: validContext,
        events: [validEvent()],
      }),
    }),
    {
      authenticatedUserID: async () => "00000000-0000-4000-8000-000000000505",
      insertTelemetryEvents: async (rows) => {
        storedRows = rows;
      },
    }
  );

  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.stored_count, 1);
  assert.equal(storedRows[0].owner_id, "00000000-0000-4000-8000-000000000505");
});

test("ingest rejects overlarge batches", async () => {
  const response = await handleTelemetryIngestRequest(
    new Request("https://example.test/functions/v1/app-telemetry-ingest", {
      method: "POST",
      body: JSON.stringify({
        context: validContext,
        events: Array.from({ length: 51 }, (_, index) => validEvent({
          client_event_id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
        })),
      }),
    }),
    {
      insertTelemetryEvents: async () => {
        throw new Error("should not store");
      },
    }
  );

  assert.equal(response.status, 413);
});

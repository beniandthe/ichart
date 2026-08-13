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
  assert.equal(row.properties.raw_chord_text, undefined);
  assert.equal(row.properties.chart_title, undefined);
  assert.equal(row.properties.error_message, undefined);
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
      assert.equal(String(url), "https://project.supabase.co/rest/v1/telemetry_events");
      assert.equal(request.headers.apikey, "server-only-key");
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

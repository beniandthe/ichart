import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { contractIDs, contractReasons, sanitizedFeatureContractProperties } from "./feature_contract_schema.mjs";
import { handleTelemetryIngestRequest, telemetryRowFromEvent } from "./telemetry_ingest.mjs";

const id = "00000000-0000-4000-8000-000000000001";
const secondID = "00000000-0000-4000-8000-000000000002";
const properties = {
  contract_id: "ink.reopen_preservation", contract_version: 1,
  operation_id: id, operation: "reopen", outcome: "violated",
  reason: "reopen_mismatch", build_source: "release_build", scope: "chord_sources",
  chart_reference: "a".repeat(64), expected_count: 3, actual_count: 0,
  expected_bytes: 1000, actual_bytes: 0, content_matches: false,
};
const event = (clientEventID, overrides = {}) => ({
  client_event_id: clientEventID, installation_id: id, session_id: id,
  event_name: "feature.contract_checked", properties, ...overrides,
});

test("shipping client and ingest agree on contract identifiers and reason vocabulary", () => {
  const client = readFileSync(new URL("../../../iChart/App/Telemetry/IChartTelemetry.swift", import.meta.url), "utf8");
  const reasons = client.match(/contractReasons: Set<String> = \[([\s\S]*?)\n    \]/);
  const ids = client.match(/case "contract_id":([\s\S]*?)(?=\n\s*case ")/);
  assert.ok(reasons);
  assert.ok(ids);
  const values = (text) => [...text.matchAll(/"([a-z0-9_.]+)"/g)].map((match) => match[1]).sort();
  assert.deepEqual(values(reasons[1]), [...contractReasons].sort());
  assert.deepEqual(values(ids[1]), [...contractIDs].sort());
});

test("strict contract envelope retains zero-valued loss evidence without source content", () => {
  const result = sanitizedFeatureContractProperties({
    ...properties, chart_title: "Private chart", raw_chord_text: "C7",
    drawing: "private bytes", severity: "critical", category: "arbitrary",
  });
  assert.deepEqual(result, properties);
});

test("contract scalar fields reject string counts, booleans, negative and excessive values", () => {
  for (const key of ["expected_count", "actual_count", "expected_bytes", "actual_bytes", "expected_point_count", "actual_point_count", "source_stroke_count", "consumed_stroke_count", "retained_stroke_count"]) {
    for (const value of ["3", true, -1, 1.5, Infinity, 1_000_000_000_001]) {
      assert.equal(sanitizedFeatureContractProperties({ ...properties, [key]: value }), null, `${key}: ${value}`);
    }
  }
});

test("contract identifiers and fixed vocabularies cannot carry arbitrary chart or chord text", () => {
  for (const key of ["contract_id", "reason", "outcome", "operation", "scope", "build_source", "layout_style", "render_mode"]) {
    assert.equal(sanitizedFeatureContractProperties({ ...properties, [key]: "private chart C7" }), null, key);
  }
  assert.equal(sanitizedFeatureContractProperties({ ...properties, operation_id: "not-a-uuid" }), null);
  assert.equal(sanitizedFeatureContractProperties({ ...properties, chart_reference: id }), null);
  assert.equal(sanitizedFeatureContractProperties({ ...properties, content_matches: "false" }), null);
  assert.equal(sanitizedFeatureContractProperties({ ...properties, contract_version: 2 }), null);
});

test("required diagnostic dimensions must be present", () => {
  for (const key of ["contract_id", "contract_version", "operation_id", "operation", "outcome", "reason", "build_source"]) {
    const missing = { ...properties };
    delete missing[key];
    assert.equal(sanitizedFeatureContractProperties(missing), null, key);
  }
});

test("strict contract event rejection preserves legacy reason and scope behavior", () => {
  assert.equal(telemetryRowFromEvent(event(id, { properties: { ...properties, actual_count: "private" } }), {}), null);
  const legacy = telemetryRowFromEvent(event(id, {
    event_name: "ink.persisted", properties: { reason: "legacy_reason", scope: "freehand", stroke_count: 5 },
  }), {});
  assert.equal(legacy.properties.reason, "legacy_reason");
  assert.equal(legacy.properties.scope, "freehand");
});

test("mixed ingest response acknowledges accepted and rejected event IDs separately", async () => {
  let inserted;
  const response = await handleTelemetryIngestRequest(new Request("https://example.test", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ events: [event(id), event(secondID, { properties: { ...properties, actual_count: "bad" } })] }),
  }), { insertTelemetryEvents: async (rows) => { inserted = rows; } });
  const body = await response.json();
  assert.equal(response.status, 202);
  assert.equal(body.stored_count, 1);
  assert.equal(body.rejected_count, 1);
  assert.deepEqual(body.accepted_event_ids, [id]);
  assert.deepEqual(body.rejected_event_ids, [secondID]);
  assert.equal(inserted.length, 1);
});

test("no acceptance is returned before durable insert completes", async () => {
  await assert.rejects(handleTelemetryIngestRequest(new Request("https://example.test", {
    method: "POST", body: JSON.stringify({ events: [event(id)] }),
  }), { insertTelemetryEvents: async () => { throw new Error("synthetic insert failure"); } }), /synthetic insert failure/);
});

test("duplicate IDs never appear in both acknowledgement lists", async () => {
  const response = await handleTelemetryIngestRequest(new Request("https://example.test", {
    method: "POST", body: JSON.stringify({ events: [event(id), event(id, { event_name: "not.allowed" })] }),
  }), { insertTelemetryEvents: async () => {} });
  const body = await response.json();
  assert.deepEqual(body.accepted_event_ids, [id]);
  assert.deepEqual(body.rejected_event_ids, []);
});


test("automatic rendering keeps typed preservation and bounded intervention dimensions", async () => {
  const automatic = {
    ...properties, contract_id: "ink.automatic_render_completion", operation: "render",
    outcome: "protected_rejection", reason: "automatic_needs_space", render_mode: "automatic",
    actual_count: 2, duration_ms: 3000.125,
    source_stroke_count: 5, consumed_stroke_count: 3, retained_stroke_count: 2,
  };
  assert.deepEqual(sanitizedFeatureContractProperties(automatic), automatic);
  for (const render_mode of ["manual", "automatic", "reviewed_automatic"]) {
    assert.equal(sanitizedFeatureContractProperties({ ...automatic, render_mode }).render_mode, render_mode);
  }
  for (const value of ["3000", true, -1, Infinity, 86_400_001]) {
    assert.equal(sanitizedFeatureContractProperties({ ...automatic, duration_ms: value }), null);
  }
  for (const reason of ["render_retained_source_changed", "render_consumed_source_remaining"]) {
    assert.equal(sanitizedFeatureContractProperties({ ...automatic, contract_id: "ink.render_preservation", outcome: "violated", reason }).reason, reason);
  }
  let inserted;
  const response = await handleTelemetryIngestRequest(new Request("https://example.test", {
    method: "POST", body: JSON.stringify({ events: [event(id, { properties: automatic })] }),
  }), { insertTelemetryEvents: async rows => { inserted = rows; } });
  assert.equal(response.status, 202);
  assert.deepEqual((await response.json()).accepted_event_ids, [id]);
  assert.equal(inserted[0].properties.render_mode, "automatic");
  assert.equal(inserted[0].properties.reason, "automatic_needs_space");
  assert.equal(inserted[0].properties.duration_ms, 3000.125);
});


test("chart and ink experience contracts admit only the fixed content-free vocabulary", async () => {
  const cases = [
    ["ink.authoring_integrity", "write", "authoring_completed_source_missing"],
    ["ink.live_canvas_visibility", "write", "authoring_canvas_invisible"],
    ["ink.authoring_responsiveness", "write", "authoring_callback_stalled"],
    ["editor.keyboard_reachability", "review", "keyboard_focused_field_occluded"],
    ["editor.keyboard_reachability", "review", "keyboard_action_unreachable"],
    ["editor.navigation_response", "navigate", "navigation_offset_mismatch"],
    ["editor.navigation_response", "navigate", "navigation_policy_mismatch"],
    ["ink.render_geometry", "render", "render_prior_geometry_changed"],
    ["ink.render_geometry", "render", "render_new_overlap"],
  ];
  const events = cases.map(([contract_id, operation, reason], index) => {
    const value = { ...properties, contract_id, operation, reason, duration_ms: 500.123456789,
      chart_title: "Do not retain", chord_text: "Do not retain", drawing: "Do not retain" };
    const clean = sanitizedFeatureContractProperties(value);
    assert.equal(clean.contract_id, contract_id);assert.equal(clean.operation, operation);assert.equal(clean.reason, reason);
    assert.equal(clean.duration_ms, 500.123);assert.ok(!JSON.stringify(clean).includes("Do not retain"));
    return event(`00000000-0000-4000-8000-${String(index + 10).padStart(12, "0")}`, { properties: value });
  });
  let stored;
  const response = await handleTelemetryIngestRequest(new Request("https://example.test", {
    method: "POST", body: JSON.stringify({ events }),
  }), { insertTelemetryEvents: async rows => { stored = rows; } });
  assert.equal(response.status, 202);assert.equal(stored.length, cases.length);
  const body = await response.json();assert.equal(body.rejected_count, 0);assert.equal(body.accepted_event_ids.length, cases.length);
  assert.ok(!JSON.stringify(stored).includes("Do not retain"));
});

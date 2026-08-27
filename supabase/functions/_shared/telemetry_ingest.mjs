import {
  authenticatedUserIDFromBearer,
  supabaseAuthorityStoreConfigurationFromEnv,
} from "./supabase_subscription_authority_store.mjs";

const maxBodyBytes = 128_000;
const maxEventsPerBatch = 50;
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const allowedEventNames = new Set([
  "app.launched",
  "app.bootstrap_completed",
  "app.open_chart",
  "app.error",
  "auth.bootstrap",
  "auth.state_changed",
  "auth.signup_started",
  "auth.signup_completed",
  "auth.signup_failed",
  "auth.signin_started",
  "auth.signin_completed",
  "auth.signin_failed",
  "auth.verification_email_requested",
  "auth.verification_email_failed",
  "auth.callback_received",
  "auth.callback_completed",
  "auth.callback_failed",
  "auth.password_reset_requested",
  "auth.password_reset_failed",
  "auth.signout_completed",
  "auth.account_deleted",
  "library.chart_created",
  "library.chart_deleted",
  "library.chart_duplicated",
  "library.project_created",
  "library.project_deleted",
  "library.pdf_library_opened",
  "editor.opened",
  "editor.closed",
  "editor.mode_changed",
  "editor.chart_setup_completed",
  "ink.persisted",
  "ink.normalization_applied",
  "ink.visibility_probe",
  "ink.coordinate_space_reprojected",
  "chord.recognition_proposed",
  "chord.recognition_committed",
  "chord.recognition_failed",
  "chord.confirmation_presented",
  "chord.correction_applied",
  "chord.batch_committed",
  "chord.preview_updated",
  "chord.preview_rendered",
  "chord.preview_discarded",
  "chord.draft_barline_added",
  "rhythm.preview_changed",
  "rhythm.confirmed",
  "pdf.export_started",
  "pdf.export_succeeded",
  "pdf.export_failed",
  "cloud.push_started",
  "cloud.push_succeeded",
  "cloud.push_failed",
  "cloud.restore_started",
  "cloud.restore_succeeded",
  "cloud.restore_failed",
  "subscription.entitlement_changed",
  "subscription.purchase_started",
  "subscription.purchase_succeeded",
  "subscription.purchase_failed",
  "subscription.restore_started",
  "subscription.restore_succeeded",
  "subscription.restore_failed",
  "forum.opened",
  "forum.post_started",
  "forum.post_succeeded",
  "forum.post_failed",
  "forum.pdf_download_started",
  "forum.pdf_download_succeeded",
  "forum.pdf_download_failed",
]);

const allowedPropertyKeys = new Set([
  "app_phase",
  "auth_state",
  "batch_size",
  "build_seen",
  "canvas_alpha",
  "canvas_background_alpha",
  "canvas_bounds_height",
  "canvas_bounds_width",
  "canvas_content_scale",
  "canvas_drawing_policy",
  "canvas_is_first_responder",
  "canvas_is_hidden",
  "canvas_is_opaque",
  "canvas_override_user_interface_style",
  "canvas_superview_user_interface_style",
  "canvas_user_interaction_enabled",
  "canvas_user_interface_style",
  "canvas_window_user_interface_style",
  "candidate_count",
  "barline_count",
  "chart_count",
  "chart_count_after",
  "chart_count_before",
  "close_race_count",
  "cloud_backed_up_count",
  "cluster_count",
  "confidence_bucket",
  "confirm_count",
  "decision",
  "duration_ms",
  "draft_count",
  "error_code",
  "feature_area",
  "flow",
  "from_mode",
  "generated_sequence_limit_count",
  "has_mask",
  "ink_tool_mode",
  "layout_style",
  "light_stroke_count",
  "local_chart_limit",
  "live_canvas_light_trait_guard_enabled",
  "measure_count",
  "median_opacity",
  "median_width",
  "min_opacity",
  "min_width",
  "max_opacity",
  "max_width",
  "matched_count",
  "mode",
  "no_read_count",
  "normalized_before_save",
  "normalization_needed",
  "page_count",
  "pdf_size_bucket",
  "plan",
  "point_count",
  "project_count",
  "reason",
  "recognition_ms",
  "recognition_target_count",
  "raw_candidate_count",
  "render_action",
  "rendered_count",
  "rendered_ink_light_pixel_ratio",
  "rendered_ink_median_luminance",
  "rendered_ink_sample_count",
  "result",
  "scope",
  "source",
  "source_coordinate_height",
  "source_coordinate_width",
  "stroke_color_max_luminance",
  "stroke_color_median_luminance",
  "stroke_color_min_luminance",
  "stroke_count",
  "subscription_status",
  "target",
  "tool_color_luminance",
  "tool_ink_type",
  "tool_is_inking",
  "tool_matches_persistent_ink",
  "tool_width",
  "target_coordinate_height",
  "target_coordinate_width",
  "to_mode",
  "trusted_count",
  "unresolved_count",
  "user_signed_in",
]);

export function createTelemetryIngestDependencies(env = globalThis.Deno?.env, options = {}) {
  const configuration = supabaseAuthorityStoreConfigurationFromEnv(env);
  const clientAPIKey = telemetryClientAPIKeyFromEnv(env);
  const fetcher = options.fetch ?? fetch;

  if (configuration === null) {
    return {};
  }

  return {
    authenticatedUserID: (request) => authenticatedUserIDFromBearer(request, configuration, fetcher),
    insertTelemetryEvents: (rows) => insertTelemetryEvents(configuration, rows, fetcher),
    validateClientAPIKey: clientAPIKey.length === 0
      ? undefined
      : (request) => request.headers.get("apikey") === clientAPIKey,
  };
}

export async function handleTelemetryIngestRequest(request, dependencies = {}) {
  if (request.method !== "POST") {
    return jsonResponse(405, {
      accepted: false,
      error: "Telemetry ingest requires POST.",
    });
  }

  if (dependencies.insertTelemetryEvents === undefined) {
    return jsonResponse(501, {
      accepted: false,
      error: "Telemetry store is not configured.",
    });
  }

  if (
    dependencies.validateClientAPIKey !== undefined
    && dependencies.validateClientAPIKey(request) !== true
  ) {
    return jsonResponse(401, {
      accepted: false,
      error: "Telemetry client key is invalid.",
    });
  }

  const body = await readJSON(request, { maxBytes: maxBodyBytes });
  if (!body.ok) {
    return jsonResponse(body.tooLarge ? 413 : 400, {
      accepted: false,
      error: body.tooLarge
        ? "Telemetry batch is too large."
        : "Request body must be valid JSON.",
    });
  }

  const incomingEvents = Array.isArray(body.value?.events) ? body.value.events : [];
  if (incomingEvents.length === 0) {
    return jsonResponse(400, {
      accepted: false,
      error: "Telemetry batch must include events.",
    });
  }

  if (incomingEvents.length > maxEventsPerBatch) {
    return jsonResponse(413, {
      accepted: false,
      error: "Telemetry batch includes too many events.",
    });
  }

  const context = sanitizedContext(body.value?.context);
  const ownerID = dependencies.authenticatedUserID === undefined
    ? null
    : await dependencies.authenticatedUserID(request);
  const normalizedEvents = incomingEvents
    .map((event) => telemetryRowFromEvent(event, context, ownerID))
    .filter((event) => event !== null);

  if (normalizedEvents.length > 0) {
    await dependencies.insertTelemetryEvents(normalizedEvents);
  }

  return jsonResponse(202, {
    accepted: true,
    stored_count: normalizedEvents.length,
    rejected_count: incomingEvents.length - normalizedEvents.length,
  });
}

export function telemetryRowFromEvent(event, context, ownerID = null) {
  if (!event || typeof event !== "object") {
    return null;
  }

  const clientEventID = normalizedUUID(event.client_event_id);
  const installationID = normalizedUUID(event.installation_id ?? context.installation_id);
  const sessionID = normalizedUUID(event.session_id ?? context.session_id);
  const eventName = normalizedString(event.event_name);
  if (
    clientEventID === null
    || installationID === null
    || sessionID === null
    || !allowedEventNames.has(eventName)
  ) {
    return null;
  }

  return {
    client_event_id: clientEventID,
    owner_id: normalizedUUID(ownerID),
    installation_id: installationID,
    session_id: sessionID,
    source: "ios",
    event_name: eventName,
    occurred_at: normalizedISODate(event.occurred_at) ?? new Date().toISOString(),
    app_version: boundedString(event.app_version ?? context.app_version, "unknown", 32),
    build_number: boundedString(event.build_number ?? context.build_number, "unknown", 32),
    platform: boundedString(event.platform ?? context.platform, "ios", 32),
    os_version: boundedString(event.os_version ?? context.os_version, "unknown", 64),
    device_model: boundedString(event.device_model ?? context.device_model, "unknown", 80),
    locale_language: boundedString(event.locale_language ?? context.locale_language, "unknown", 32),
    time_zone_offset_minutes: boundedInteger(
      event.time_zone_offset_minutes ?? context.time_zone_offset_minutes,
      -840,
      840,
      0
    ),
    properties: sanitizedProperties(event.properties),
  };
}

function sanitizedContext(value) {
  const context = value && typeof value === "object" ? value : {};
  return {
    installation_id: normalizedUUID(context.installation_id),
    session_id: normalizedUUID(context.session_id),
    app_version: boundedString(context.app_version, "unknown", 32),
    build_number: boundedString(context.build_number, "unknown", 32),
    platform: boundedString(context.platform, "ios", 32),
    os_version: boundedString(context.os_version, "unknown", 64),
    device_model: boundedString(context.device_model, "unknown", 80),
    locale_language: boundedString(context.locale_language, "unknown", 32),
    time_zone_offset_minutes: boundedInteger(context.time_zone_offset_minutes, -840, 840, 0),
  };
}

export function sanitizedProperties(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return {};
  }

  const entries = Object.entries(value)
    .filter(([key]) => allowedPropertyKeys.has(key))
    .sort(([left], [right]) => left.localeCompare(right))
    .slice(0, 40);
  const sanitized = {};

  for (const [key, rawValue] of entries) {
    const normalizedValue = sanitizedPropertyValue(rawValue);
    if (normalizedValue !== undefined) {
      sanitized[key] = normalizedValue;
    }
  }

  return sanitized;
}

function sanitizedPropertyValue(value) {
  if (value === null) {
    return null;
  }

  switch (typeof value) {
    case "boolean":
      return value;
    case "number":
      return Number.isFinite(value) ? roundedNumber(value) : undefined;
    case "string":
      return normalizedString(value).slice(0, 160);
    default:
      return undefined;
  }
}

function roundedNumber(value) {
  if (Number.isInteger(value)) {
    return value;
  }

  return Math.round(value * 1000) / 1000;
}

function telemetryClientAPIKeyFromEnv(env) {
  return normalizedString(
    envValue(env, "SUPABASE_ANON_KEY")
      ?? envValue(env, "SUPABASE_PUBLISHABLE_KEY")
      ?? envValue(env, "ICHART_TELEMETRY_CLIENT_API_KEY")
  );
}

async function insertTelemetryEvents(configuration, rows, fetcher) {
  const url = supabaseURL(configuration, "/rest/v1/telemetry_events");
  const response = await fetcher(url, {
    method: "POST",
    headers: supabaseRESTHeaders(configuration, "resolution=ignore-duplicates,return=minimal"),
    body: JSON.stringify(rows),
  });

  if (!response.ok) {
    const responseText = await response.text();
    throw new Error(`Telemetry insert failed: ${response.status} ${responseText.slice(0, 240)}`);
  }
}

async function readJSON(request, options = {}) {
  const maxBytes = options.maxBytes ?? 64_000;
  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxBytes) {
    return { ok: false, tooLarge: true };
  }

  const text = await request.text();
  if (new TextEncoder().encode(text).byteLength > maxBytes) {
    return { ok: false, tooLarge: true };
  }

  try {
    return { ok: true, value: JSON.parse(text) };
  } catch {
    return { ok: false, tooLarge: false };
  }
}

function supabaseURL(configuration, path) {
  return new URL(path, `${configuration.supabaseURL}/`);
}

function supabaseRESTHeaders(configuration, prefer) {
  return {
    apikey: configuration.secretKey,
    authorization: `Bearer ${configuration.secretKey}`,
    "content-type": "application/json",
    ...(prefer ? { prefer } : {}),
  };
}

function boundedString(value, fallback, maximumLength) {
  const normalized = normalizedString(value).slice(0, maximumLength);
  return normalized.length > 0 ? normalized : fallback;
}

function boundedInteger(value, minimum, maximum, fallback) {
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return fallback;
  }

  return Math.min(maximum, Math.max(minimum, Math.round(number)));
}

function normalizedISODate(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return null;
  }

  return date.toISOString();
}

function normalizedUUID(value) {
  const candidate = normalizedString(value).toLowerCase();
  return uuidPattern.test(candidate) ? candidate : null;
}

function normalizedString(value) {
  if (typeof value === "string") {
    return value.trim();
  }

  if (value === null || value === undefined) {
    return "";
  }

  return String(value).trim();
}

function envValue(env, key) {
  if (env && typeof env.get === "function") {
    return env.get(key);
  }

  return env?.[key];
}

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

// Content-free diagnostic envelope. Categories and severity are assigned by
// server-side rules, never by a client-provided bug label.
export const contractIDs = new Set([
  "chart.save", "chart.load", "chart.save_readback", "ink.reopen_preservation",
  "ink.render_preservation", "ink.rotation_preservation", "chart.export",
  "ink.automatic_render_completion",
  "ink.authoring_integrity", "ink.authoring_responsiveness", "ink.live_canvas_visibility",
  "editor.keyboard_reachability", "editor.navigation_response", "ink.render_geometry",
]);

export const contractReasons = new Set([
  "save_completed", "save_failed", "load_completed", "load_failed", "first_launch",
  "readback_matches", "readback_mismatch", "readback_failed", "baseline_missing",
  "baseline_changed", "reopen_matches", "reopen_mismatch", "render_complete",
  "render_source_missing", "render_incomplete_coverage", "render_unresolved",
  "render_empty", "render_canvas_unavailable", "render_repeat_review_required",
  "render_rejected_mutated", "render_canvas_not_cleared", "rotation_complete",
  "rotation_stroke_count_changed", "rotation_point_count_changed",
  "rotation_nonfinite_geometry", "export_completed", "export_failed",
  "render_retained_source_changed", "render_consumed_source_remaining",
  "automatic_render_complete", "automatic_no_read", "automatic_recognition_review",
  "automatic_needs_space", "automatic_placement_unavailable", "automatic_unrepresented_ink",
  "automatic_adjacent_writing",
  "authoring_completed_source_missing", "authoring_source_preserved",
  "authoring_callback_stalled", "authoring_responsive",
  "authoring_canvas_invisible", "authoring_canvas_visible",
  "keyboard_focused_field_occluded", "keyboard_action_unreachable", "keyboard_controls_reachable",
  "navigation_offset_mismatch", "navigation_policy_mismatch", "navigation_response_matches",
  "render_prior_geometry_changed", "render_new_overlap", "render_geometry_preserved",
]);

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const scopes = new Set([
  "library", "chart", "page", "header", "chords", "rhythm", "chord_sources",
  "note_sources", "roadmap_sources",
]);
const numericCounts = new Set([
  "expected_count", "actual_count", "expected_bytes", "actual_bytes",
  "expected_point_count", "actual_point_count",
  "source_stroke_count", "consumed_stroke_count", "retained_stroke_count",
]);
const required = ["contract_id", "contract_version", "operation_id", "operation", "outcome", "reason", "build_source"];
const enumFields = {
  contract_id: contractIDs,
  reason: contractReasons,
  operation: new Set(["save", "load", "save_readback", "reopen", "render", "rotate", "export", "write", "review", "navigate"]),
  outcome: new Set(["passed", "violated", "unknown", "protected_rejection"]),
  build_source: new Set(["debug_build", "release_build"]),
  render_mode: new Set(["manual", "automatic", "reviewed_automatic"]),
  layout_style: new Set(["simpleChordSheet", "rhythmSectionSheet", "leadSheet"]),
  scope: scopes,
};

export function sanitizedFeatureContractProperties(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const result = {};
  for (const [key, raw] of Object.entries(value)) {
    if (enumFields[key]) {
      if (!enumFields[key].has(raw)) return null;
      result[key] = raw;
    } else if (numericCounts.has(key)) {
      if (!Number.isSafeInteger(raw) || raw < 0 || raw > 1_000_000_000_000) return null;
      result[key] = raw;
    } else if (key === "contract_version") {
      if (raw !== 1) return null;
      result[key] = raw;
    } else if (key === "operation_id") {
      if (typeof raw !== "string" || !uuid.test(raw)) return null;
      result[key] = raw.toLowerCase();
    } else if (key === "chart_reference") {
      if (typeof raw !== "string" || !/^[0-9a-f]{64}$/i.test(raw)) return null;
      result[key] = raw.toLowerCase();
    } else if (key === "content_matches") {
      if (typeof raw !== "boolean") return null;
      result[key] = raw;
    } else if (key === "duration_ms") {
      if (typeof raw !== "number" || !Number.isFinite(raw) || raw < 0 || raw > 86_400_000) return null;
      result[key] = Math.round(raw * 1000) / 1000;
    }
    // Unknown keys (including raw content and client-supplied severity) drop.
  }
  return required.every((key) => Object.hasOwn(result, key)) ? result : null;
}

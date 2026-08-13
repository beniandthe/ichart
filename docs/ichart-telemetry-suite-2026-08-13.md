# iChart Telemetry Suite

Date: 2026-08-13

## Goal

Give iChart enough production visibility to answer:

- Are people launching, signing in, creating charts, opening the editor, exporting PDFs, backing up, restoring, purchasing, and using Forums?
- Which editor tools are actually used?
- Where do flows fail without a crash?
- For support issues like invisible Apple Pencil ink, what is the app saving/rendering at an aggregate level?

## Privacy Boundary

Telemetry must not collect chart titles, song titles, artist names, emails, names, raw chord text, handwritten drawing data, PDF files, screenshots, or chart JSON.

Allowed telemetry is limited to event names, app/build/device/iPadOS context, coarse workflow outcomes, counts, timings, confidence buckets, and aggregate PencilKit appearance stats.

The app-side sanitizer and Edge Function both enforce allowlists. Unknown event names are dropped. Unknown property keys are dropped.

## Backend

Migration:

- `supabase/migrations/20260813192919_telemetry_foundation.sql`

Raw storage:

- `public.telemetry_events`
- RLS enabled.
- All grants revoked from `public`, `anon`, and `authenticated`.
- `service_role` can select/insert/delete.
- `owner_id` is nullable and uses `on delete set null`.

Edge Function:

- `app-telemetry-ingest`
- `verify_jwt = false` intentionally, so signed-out auth/setup failures can be reported.
- When `SUPABASE_ANON_KEY`, `SUPABASE_PUBLISHABLE_KEY`, or `ICHART_TELEMETRY_CLIENT_API_KEY` is configured, the function requires the app `apikey` header before accepting a batch.
- If a valid bearer session is present, the function resolves `owner_id`.
- The function inserts with the server-side secret key and sanitizes every payload.

Rollups:

- `private.telemetry_daily_event_counts`
- `private.telemetry_daily_feature_usage`
- `private.telemetry_recent_ink_diagnostics`

Retention helper:

- `private.purge_old_telemetry_events(retain_days integer default 180)`

## Event Areas

App/auth:

- `app.launched`
- `app.bootstrap_completed`
- `app.open_chart`
- `auth.signup_started`, `auth.signup_completed`, `auth.signup_failed`
- `auth.signin_started`, `auth.signin_completed`, `auth.signin_failed`
- `auth.verification_email_requested`, `auth.verification_email_failed`
- `auth.callback_received`, `auth.callback_completed`, `auth.callback_failed`
- `auth.password_reset_requested`, `auth.password_reset_failed`
- `auth.signout_completed`, `auth.account_deleted`

Library/editor:

- `library.chart_created`, `library.chart_deleted`, `library.chart_duplicated`
- `library.project_created`, `library.project_deleted`
- `library.pdf_library_opened`
- `editor.opened`, `editor.closed`, `editor.mode_changed`, `editor.chart_setup_completed`

Ink/chord/rhythm:

- `ink.persisted`
- `ink.normalization_applied`
- `ink.visibility_probe`
- `chord.recognition_proposed`
- `chord.confirmation_presented`
- `chord.recognition_committed`
- `chord.recognition_failed`
- `chord.correction_applied`
- `chord.batch_committed`
- `rhythm.preview_changed`
- `rhythm.confirmed`

Export/cloud/subscription/forum:

- `pdf.export_started`, `pdf.export_succeeded`, `pdf.export_failed`
- `cloud.push_started`, `cloud.push_succeeded`, `cloud.push_failed`
- `cloud.restore_started`, `cloud.restore_succeeded`, `cloud.restore_failed`
- `subscription.entitlement_changed`
- `subscription.purchase_started`, `subscription.purchase_succeeded`, `subscription.purchase_failed`
- `subscription.restore_started`, `subscription.restore_succeeded`, `subscription.restore_failed`
- `forum.opened`
- `forum.post_started`, `forum.post_succeeded`, `forum.post_failed`
- `forum.pdf_download_started`, `forum.pdf_download_succeeded`, `forum.pdf_download_failed`

## LJ-Class Ink Diagnosis

For `ink.persisted`, `ink.normalization_applied`, and `ink.visibility_probe`, the app records:

- `scope`
- `stroke_count`
- `point_count`
- `light_stroke_count`
- `stroke_color_min_luminance`, `stroke_color_median_luminance`, `stroke_color_max_luminance`
- `min_opacity`, `median_opacity`, `max_opacity`
- `min_width`, `median_width`, `max_width`
- `has_mask`
- `normalization_needed`
- `normalized_before_save`
- `tool_ink_type`, `tool_color_luminance`
- `canvas_user_interface_style`, `canvas_background_alpha`, `canvas_is_opaque`
- `rendered_ink_median_luminance`, `rendered_ink_light_pixel_ratio`, `rendered_ink_sample_count`

This distinguishes:

- white or near-white persisted ink
- dark ink with near-zero opacity
- tiny point/stroke sizes
- masked/clipped strokes
- normalization applied but still invisible

## First Queries

Daily feature usage:

```sql
select *
from private.telemetry_daily_feature_usage
where event_day >= current_date - 14
order by event_day desc, feature_area;
```

Ink diagnostics:

```sql
select *
from private.telemetry_recent_ink_diagnostics
order by received_at desc
limit 100;
```

Failure hot spots:

```sql
select
    event_name,
    properties ->> 'error_code' as error_code,
    app_version,
    build_number,
    count(*) as failures
from public.telemetry_events
where received_at >= now() - interval '7 days'
    and event_name like '%.%_failed'
group by 1, 2, 3, 4
order by failures desc;
```

Editor tool use:

```sql
select
    properties ->> 'to_mode' as mode,
    count(*) as switches,
    count(distinct installation_id) as installations
from public.telemetry_events
where event_name = 'editor.mode_changed'
    and received_at >= now() - interval '14 days'
group by 1
order by switches desc;
```

## Release Checklist

- Run Node ingest tests.
- Run Xcode telemetry/privacy tests.
- Deploy migration.
- Deploy `app-telemetry-ingest`.
- Confirm a request without the configured client API key is rejected.
- Confirm a signed-out launch event can insert without `owner_id`.
- Confirm a signed-in event resolves `owner_id`.
- Confirm raw chart/title/chord-like keys are dropped.
- Update customer-facing privacy copy before shipping telemetry to App Store users.

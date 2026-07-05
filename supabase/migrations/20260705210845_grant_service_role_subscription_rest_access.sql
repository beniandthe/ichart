-- Supabase's newer Data API defaults no longer expose public tables to
-- service_role implicitly. Keep app clients read-only, but allow the trusted
-- server verifier/local QA harness to write subscription authority rows.
grant select, insert, update, delete on table public.subscriptions to service_role;

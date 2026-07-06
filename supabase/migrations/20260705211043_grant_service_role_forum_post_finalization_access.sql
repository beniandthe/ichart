-- Server-side moderation/finalization uses the service role through the Data
-- API to publish a pending post and mark its uploaded PDF as validated. App
-- clients remain constrained by authenticated grants and RLS policies.
grant select, update on table public.forum_chart_posts to service_role;

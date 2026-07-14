-- Forum post action Edge Function support.
--
-- The client still submits forum PDFs through existing authenticated Storage/RLS
-- paths. This grant is only for the JWT-protected Edge Function that validates
-- iChart-owned metadata/provenance, publishes pending posts, and lets owners
-- withdraw or remove their own forum posts without exposing moderation columns
-- to the public client.

grant select on table public.forum_songs to service_role;
grant select, update on table public.forum_chart_posts to service_role;
grant execute on function public.finalize_forum_chart_post_pdf(uuid, bigint, text) to service_role;

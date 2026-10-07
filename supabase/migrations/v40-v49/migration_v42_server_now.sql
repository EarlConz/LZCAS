-- ═══════════════════════════════════════════════════════════════════
-- Migration v42 — server_now(), so the app can stop trusting the device
--
-- Adds a read-only function returning the database's clock.
--
-- ── Why ────────────────────────────────────────────────────────────
-- Whether an announcement is "live" was decided in two places with two
-- different clocks: the RLS policy and every query use the SERVER's
-- now(), while the app's Announcement.isCurrent() used DateTime.now()
-- on the DEVICE. Those agree only when the device clock is right.
--
-- On a device set weeks ahead, an announcement with a future end date
-- reads as already ended: staff still see the row (their list does not
-- filter on it) but it is labelled "Ended", while members have it
-- filtered out entirely and never learn it exists. One wrong clock, and
-- the office believes it posted a notice that nobody received.
--
-- The app calls this once per session, measures the offset against its
-- own clock, and applies that offset everywhere it asks "what time is
-- it". Nothing is written and nothing is per-user, so this is safe for
-- any authenticated caller.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_server_now_v42.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.server_now()
returns timestamptz
language sql
stable
as $$
  select now();
$$;

comment on function public.server_now() is
  'The database clock. Called by the app once per session so it can correct for a wrong device clock before deciding what is current.';

revoke all on function public.server_now() from public;
grant execute on function public.server_now() to authenticated;

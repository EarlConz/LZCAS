-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v40_announcement_reads.sql
--
-- Drops the reads table. Destructive in one direction that matters:
-- every record of who has seen what is lost, so re-applying v40
-- afterwards backfills everything as seen again and any announcement
-- posted in between will never pop.
--
-- The app half is harmless to leave in place — a client that cannot
-- read `announcement_reads` shows no popup rather than erroring — so
-- prefer NOT running this. If the popup is misbehaving, the
-- non-destructive fix is to mark everything seen for everyone:
--
--   insert into public.announcement_reads (profile_id, announcement_id)
--   select p.id, a.id from public.profiles p cross join public.announcements a
--   on conflict do nothing;
--
-- That silences it without losing the history.
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "announcement_reads_select_own" on public.announcement_reads;
drop policy if exists "announcement_reads_insert_own" on public.announcement_reads;

drop index if exists public.idx_announcement_reads_profile;

drop table if exists public.announcement_reads;

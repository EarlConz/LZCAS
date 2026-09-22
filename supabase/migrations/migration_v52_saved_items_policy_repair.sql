-- ═══════════════════════════════════════════════════════════════════
-- Migration v52 — Reassert the member_saved_items policies
--
-- Repairs a database where `member_saved_items` has RLS on and either no
-- policies or the pre-v41 ones, which shows up in the app as:
--
--   [setAnnouncementSaved] failed: PostgrestException(... code: 42501,
--   new row violates row-level security policy for table
--   "member_saved_items")
--
-- — a member taps the star on an announcement and nothing is kept. The
-- failure is caught and logged, never surfaced, so the only symptom is a
-- star that will not stay lit.
--
-- ── Why the ledger did not catch it ────────────────────────────────
-- v45 records v41 as applied when the `profile_id` COLUMN exists. It
-- never checks the policies, so a database whose policies were replaced
-- or wiped afterwards — the Supabase dashboard's one-click "Enable RLS"
-- does exactly this, as v46 found on `app_config` — reads as v41-applied
-- while behaving as though it is not.
--
-- ── Why not just re-run v41 ────────────────────────────────────────
-- Because it cannot be. v41 says "safe to re-run" and is not: step 2
-- backfills `from public.profiles p where p.member_id = s.member_id`,
-- and step 6 drops `member_id`. On a database where v41 already
-- succeeded, a second run aborts with
--   ERROR: column s.member_id does not exist
-- before reaching the policies. This file is the re-runnable half.
--
-- Changes nothing on a healthy database: the policies it writes are
-- character-for-character the ones v41 ends with.
--
-- Safe to re-run. Rollback: none needed — reasserting correct policies
-- has no state to undo. To remove them entirely, see
-- supabase/rollbacks/rollback_saved_items_by_profile_v41.sql.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Refuse to run on a database that never got v41 ──────────────
-- Writing policies against `profile_id` where the column does not exist
-- would fail confusingly halfway. Fail early and say which file to run.
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'member_saved_items'
       and column_name = 'profile_id'
  ) then
    raise exception
      'v52 aborted: member_saved_items has no profile_id column, so v41 never ran here. Apply migration_v41_saved_items_by_profile.sql first; this file only repairs the policies it leaves behind.';
  end if;
end $$;

-- ── 2. RLS on ──────────────────────────────────────────────────────
alter table public.member_saved_items enable row level security;

-- ── 3. The v41 policies, reasserted ────────────────────────────────
-- Dropped by name first: a leftover policy with the same name but a
-- pre-v41 body would otherwise survive and keep rejecting writes.
drop policy if exists "saved_items_select" on public.member_saved_items;
drop policy if exists "saved_items_insert" on public.member_saved_items;
drop policy if exists "saved_items_delete" on public.member_saved_items;

-- Staff may READ these, so the admin screen can say how many accounts
-- have kept a notice before it is archived. Nobody writes on anyone
-- else's behalf, staff included.
create policy "saved_items_select" on public.member_saved_items
  for select to authenticated
  using (public.is_staff() or profile_id = auth.uid());

create policy "saved_items_insert" on public.member_saved_items
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy "saved_items_delete" on public.member_saved_items
  for delete to authenticated
  using (profile_id = auth.uid());

-- No UPDATE policy, as in v41: a saved item is created or removed,
-- never edited.

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (52, 'saved_items_policy_repair')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- Three rows, and the insert policy's with_check reads (profile_id = auth.uid()):
--   select policyname, cmd, qual, with_check
--     from pg_policies
--    where schemaname = 'public' and tablename = 'member_saved_items';
--
-- Then in the app: as a member, star an announcement, leave the tab and
-- come back. The star stays lit and the console prints nothing.

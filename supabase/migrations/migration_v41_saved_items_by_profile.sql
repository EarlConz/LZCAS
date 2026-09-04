-- ═══════════════════════════════════════════════════════════════════
-- Migration v41 — Saved items keyed on the ACCOUNT, not the member row
--
-- Re-keys `member_saved_items` from `member_id` (bigint -> members) to
-- `profile_id` (uuid -> profiles), so any account that can log in can
-- keep an announcement.
--
-- ── Why ────────────────────────────────────────────────────────────
-- v39 made branch cashiers an announcement audience. A branch cashier
-- is a staff account: a row in `profiles` with no `members` row at all,
-- so there was no value to put in `member_id` — not even the right
-- type — and the save control had to be hidden for them. That was a
-- consequence of a table designed before staff could receive
-- announcements, not a decision anyone made.
--
-- `profiles.id` IS `auth.uid()`, so this also simplifies every policy
-- from a join to a column comparison, and matches how v40's
-- `announcement_reads` is already keyed.
--
-- ── Safety ─────────────────────────────────────────────────────────
-- Every existing row was created by a logged-in member, so each maps to
-- exactly one profile. If ANY row cannot be mapped this migration
-- ABORTS rather than dropping data — investigate before re-running.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_saved_items_by_profile_v41.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Add the new key ─────────────────────────────────────────────
alter table public.member_saved_items
  add column if not exists profile_id uuid references public.profiles (id) on delete cascade;

-- ── 2. Backfill from the owning member's profile ───────────────────
update public.member_saved_items s
   set profile_id = p.id
  from public.profiles p
 where p.member_id = s.member_id
   and s.profile_id is null;

-- ── 3. Refuse to continue if anything failed to map ────────────────
do $$
declare
  orphans integer;
begin
  select count(*) into orphans
    from public.member_saved_items
   where profile_id is null;

  if orphans > 0 then
    raise exception
      'v41 aborted: % saved item(s) have no matching profile. These belong to member rows with no account and cannot be re-keyed. Investigate before re-running; nothing has been dropped.',
      orphans;
  end if;

  raise notice 'v41: all saved items re-keyed to profile_id.';
end $$;

alter table public.member_saved_items
  alter column profile_id set not null;

-- ── 4. Move the indexes and constraints across ─────────────────────
drop index if exists public.uq_saved_announcement;
drop index if exists public.uq_saved_birthday;
drop index if exists public.idx_saved_member;

-- Partial uniques rather than one composite: a plain UNIQUE over nullable
-- columns treats NULLs as distinct, so it would let the same item be saved
-- twice.
create unique index if not exists uq_saved_announcement
  on public.member_saved_items (profile_id, announcement_id)
  where item_kind = 'announcement';

create unique index if not exists uq_saved_birthday
  on public.member_saved_items (profile_id, birthday_year)
  where item_kind = 'birthday';

create index if not exists idx_saved_profile
  on public.member_saved_items (profile_id, saved_at desc);

-- ── 5. Drop the old policies FIRST ─────────────────────────────────
-- The v36 policies read `member_id` in their USING/WITH CHECK clauses, so
-- Postgres refuses to drop the column while they exist. They have to go
-- before the column, not after it — the reverse order fails with
-- "cannot drop column member_id ... policy saved_items_select depends on it".
drop policy if exists "saved_items_select" on public.member_saved_items;
drop policy if exists "saved_items_insert" on public.member_saved_items;
drop policy if exists "saved_items_delete" on public.member_saved_items;

-- ── 6. Retire the old key ──────────────────────────────────────────
alter table public.member_saved_items drop column if exists member_id;

comment on table public.member_saved_items is
  'Announcements and birthday greetings an ACCOUNT has kept. Keyed on profiles.id (= auth.uid()), so staff accounts with no members row can save too.';

-- ── 7. Recreate them against the new key ───────────────────────────
-- Now a column comparison rather than a join, because profiles.id IS
-- auth.uid(). Staff may still READ these, so the admin screen can warn that
-- N accounts have saved a notice before it is archived. They still may not
-- write them: nobody gets to star or unstar on someone else's behalf.
create policy "saved_items_select" on public.member_saved_items
  for select to authenticated
  using (public.is_staff() or profile_id = auth.uid());

create policy "saved_items_insert" on public.member_saved_items
  for insert to authenticated
  with check (profile_id = auth.uid());

create policy "saved_items_delete" on public.member_saved_items
  for delete to authenticated
  using (profile_id = auth.uid());

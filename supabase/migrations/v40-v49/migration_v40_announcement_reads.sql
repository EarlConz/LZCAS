-- ═══════════════════════════════════════════════════════════════════
-- Migration v40 — Announcement reads (unseen notices pop up on open)
--
-- Records which accounts have already seen which announcement, so an
-- unseen one can be shown once when the account next opens and never
-- again after it is dismissed.
--
-- ── Keyed on profiles.id, NOT members.id ───────────────────────────
-- This is the one structural difference from `member_saved_items`,
-- which keys on members.id. Branch cashiers are staff accounts with no
-- `members` row, so a member-keyed table could not record their reads
-- at all — and branches are an announcement audience as of v39.
-- auth.uid() IS profiles.id, which also makes the RLS trivial.
--
-- ── Existing announcements are backfilled as SEEN ──────────────────
-- Without this, every announcement ever posted would pop for every
-- account the first time they open the app after this ships — the
-- feature would introduce itself by spamming. Anything posted from
-- here on has no read row and behaves normally.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_announcement_reads_v40.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. The table ───────────────────────────────────────────────────
create table if not exists public.announcement_reads (
  id              bigint generated always as identity primary key,
  profile_id      uuid        not null
                    references public.profiles (id) on delete cascade,
  announcement_id bigint      not null
                    references public.announcements (id) on delete cascade,
  seen_at         timestamptz not null default now(),
  constraint uq_announcement_read unique (profile_id, announcement_id)
);

-- The only query this table serves: "which of these has this account
-- already seen?" — so the index leads with profile_id.
create index if not exists idx_announcement_reads_profile
  on public.announcement_reads (profile_id, announcement_id);

-- ── 2. RLS — an account may only read and write its OWN rows ───────
alter table public.announcement_reads enable row level security;

drop policy if exists "announcement_reads_select_own" on public.announcement_reads;
create policy "announcement_reads_select_own" on public.announcement_reads
  for select to authenticated
  using (profile_id = auth.uid());

drop policy if exists "announcement_reads_insert_own" on public.announcement_reads;
create policy "announcement_reads_insert_own" on public.announcement_reads
  for insert to authenticated
  with check (profile_id = auth.uid());

-- Deliberately no UPDATE and no DELETE policy. "Seen" is a fact about
-- something that already happened; there is no legitimate reason for a
-- client to rewrite or erase it, and the absence of a policy is what
-- enforces that.

-- ── 3. Backfill everything that already exists as seen ─────────────
insert into public.announcement_reads (profile_id, announcement_id)
select p.id, a.id
  from public.profiles p
 cross join public.announcements a
on conflict (profile_id, announcement_id) do nothing;

do $$
declare
  n integer;
begin
  select count(*) into n from public.announcement_reads;
  raise notice 'v40: % existing (account, announcement) pair(s) marked as already seen.', n;
end $$;

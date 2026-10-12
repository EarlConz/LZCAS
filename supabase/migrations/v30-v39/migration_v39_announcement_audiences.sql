-- ═══════════════════════════════════════════════════════════════════
-- Migration v39 — Announcement audiences: Everyone / Branches / Members
--
-- Replaces the v36 audience set ('all', 'resellers', 'members') with
-- ('all', 'branches', 'members'), changing what two of the three mean:
--
--   all       unchanged — every account that can see announcements.
--   branches  NEW — branch cashier accounts. The first audience that
--             addresses staff rather than customers.
--   members   WIDENED — now members AND resellers. Previously 'members'
--             meant plain members only, with resellers a separate audience.
--
-- ── Data change, read this before running ──────────────────────────
-- There is no longer a reseller-only audience, so existing rows with
-- audience = 'resellers' are migrated to 'members'. That WIDENS them:
-- an announcement previously visible only to resellers becomes visible
-- to plain members too. The count is reported below. If any of those
-- notices are reseller-sensitive, archive them before running this.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_announcement_audiences_v39.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Report what is about to be rewritten ────────────────────────
do $$
declare
  n integer;
begin
  select count(*) into n from public.announcements where audience = 'resellers';
  if n > 0 then
    raise notice 'v39: % announcement(s) with audience=''resellers'' will become ''members'' and be visible to plain members too.', n;
  else
    raise notice 'v39: no reseller-only announcements to migrate.';
  end if;
end $$;

-- ── 2. Widen the constraint before rewriting, so both old and new
--       values are briefly legal and the update cannot trip it ──────
alter table public.announcements
  drop constraint if exists announcements_audience_check;

alter table public.announcements
  add constraint announcements_audience_check
  check (audience in ('all', 'resellers', 'branches', 'members'));

update public.announcements
   set audience = 'members'
 where audience = 'resellers';

-- ── 3. Settle on the final three ───────────────────────────────────
alter table public.announcements
  drop constraint announcements_audience_check;

alter table public.announcements
  add constraint announcements_audience_check
  check (audience in ('all', 'branches', 'members'));

comment on column public.announcements.audience is
  'all = every account; branches = branch cashiers; members = members and resellers.';

-- ── 4. Re-point the read policy at the new meanings ────────────────
-- Unchanged from v36 except the audience arm: staff still see everything,
-- ends_at is still deliberately NOT filtered here (an expired announcement
-- must stay readable so saved copies keep working), and there is still no
-- DELETE policy.
drop policy if exists "announcements_select" on public.announcements;
create policy "announcements_select" on public.announcements
  for select to authenticated
  using (
    public.is_staff()
    or (
      archived_at is null
      and published_at <= now()
      and exists (
        select 1 from public.profiles pr
        where pr.id = auth.uid()
          and (
            announcements.audience = 'all'
            or (announcements.audience = 'branches'
                and pr.role = 'branch_cashier')
            or (announcements.audience = 'members'
                and pr.role in ('member', 'reseller'))
          )
      )
    )
  );

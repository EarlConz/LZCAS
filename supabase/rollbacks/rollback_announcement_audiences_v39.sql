-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v39_announcement_audiences.sql
--
-- Restores the v36 audience set ('all', 'resellers', 'members') and the
-- v36 read policy.
--
-- ── This does NOT restore data ─────────────────────────────────────
-- v39 rewrote 'resellers' rows to 'members'. That rewrite is not
-- reversible — once merged, nothing records which of the 'members' rows
-- used to be reseller-only. Running this leaves them as 'members', which
-- under the v36 meaning is *narrower* than they were originally (plain
-- members only, resellers excluded).
--
-- Any 'branches' announcement posted after v39 has no v36 equivalent.
-- They are archived rather than deleted, so nobody's saved copy breaks.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Retire announcements the old model cannot express ───────────
update public.announcements
   set archived_at = coalesce(archived_at, now())
 where audience = 'branches';

update public.announcements
   set audience = 'all'
 where audience = 'branches';

-- ── 2. Restore the v36 constraint ──────────────────────────────────
alter table public.announcements
  drop constraint if exists announcements_audience_check;

alter table public.announcements
  add constraint announcements_audience_check
  check (audience in ('all', 'resellers', 'members'));

comment on column public.announcements.audience is
  'all = every account; resellers = verified resellers; members = plain members.';

-- ── 3. Restore the v36 read policy ─────────────────────────────────
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
            or (announcements.audience = 'resellers' and pr.role = 'reseller')
            or (announcements.audience = 'members'   and pr.role = 'member')
          )
      )
    )
  );

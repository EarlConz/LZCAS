-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v43_announcement_staff_bypass.sql
--
-- Restores the is_staff() bypass on the announcements read policy.
--
-- Be aware of what this brings back: because v28 counts branch cashiers
-- as staff, this again lets them read EVERY announcement of every
-- audience, archived ones included — a "Members only" notice reappears
-- in branch terminals. Only run this if v43 broke something worse.
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- Migration v43 — Branch cashiers are an AUDIENCE, not managers
--
-- Narrows the announcements read policy's bypass from is_staff() to
-- is_admin().
--
-- ── The bug ────────────────────────────────────────────────────────
-- v28 added 'branch_cashier' to is_staff(), so it could run POS. The
-- v36 announcements policy opened with:
--
--   using (public.is_staff() or (<audience check>))
--
-- which was correct while announcements only went to members and
-- resellers — "staff" meant the back office, reading its own notices.
--
-- v39 made branches an audience. From that point a branch cashier
-- matched the FIRST arm and the audience check never ran for them, so
-- they saw every announcement of every audience, archived ones
-- included. A notice sent to "Members only" showed up in a branch
-- terminal.
--
-- ── The fix ────────────────────────────────────────────────────────
-- Only admins manage announcements: is_admin() already gates INSERT and
-- UPDATE, and the admin page is the only screen that lists archived
-- ones. Cashiers and inventory have no announcements UI at all, so
-- narrowing the bypass costs them nothing they were using.
--
-- Everyone else — members, resellers AND branch cashiers — now goes
-- through the audience check, which is what makes an audience mean
-- anything.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_announcement_staff_bypass_v43.sql
-- ═══════════════════════════════════════════════════════════════════

drop policy if exists "announcements_select" on public.announcements;
create policy "announcements_select" on public.announcements
  for select to authenticated
  using (
    -- Admins manage these, so they see everything including archived.
    public.is_admin()
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

-- ── Verify ─────────────────────────────────────────────────────────
-- As a branch cashier, this must return only 'all' and 'branches' rows:
--   select id, title, audience from public.announcements order by id;

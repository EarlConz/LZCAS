-- ═══════════════════════════════════════════════════════════════════
-- Rollback v51 — Main cashiers can post announcements
--
-- Restores the v43 read policy, the v36 write policies and the v44 bucket
-- policies, i.e. admins only. Announcements a cashier already posted are
-- left alone — they are normal rows; they simply stop being editable by
-- their author.
--
-- Run only if the cashier announcement UI is pulled from the build too:
-- the app shows the compose button to cashiers whenever their role says
-- so, and with these policies back, saving would fail at the database.
-- ═══════════════════════════════════════════════════════════════════

-- ── Announcements ──────────────────────────────────────────────────
drop policy if exists "announcements_select" on public.announcements;
create policy "announcements_select" on public.announcements
  for select to authenticated
  using (
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

drop policy if exists "announcements_insert" on public.announcements;
create policy "announcements_insert" on public.announcements
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "announcements_update" on public.announcements;
create policy "announcements_update" on public.announcements
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- ── Poster bucket ──────────────────────────────────────────────────
drop policy if exists "announcement-media read"   on storage.objects;
drop policy if exists "announcement-media write"  on storage.objects;
drop policy if exists "announcement-media update" on storage.objects;
drop policy if exists "announcement-media delete" on storage.objects;

create policy "announcement-media read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'announcement-media'
    and (
      public.is_admin()
      or exists (
        select 1 from public.announcements a
        where a.image_path = storage.objects.name
      )
      or exists (
        select 1 from public.app_config c
        where c.key = 'birthday_greeting_image'
          and c.value = storage.objects.name
      )
    )
  );

create policy "announcement-media write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'announcement-media' and public.is_admin());

create policy "announcement-media update" on storage.objects
  for update to authenticated
  using (bucket_id = 'announcement-media' and public.is_admin())
  with check (bucket_id = 'announcement-media' and public.is_admin());

create policy "announcement-media delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'announcement-media' and public.is_admin());

-- ── Helpers ────────────────────────────────────────────────────────
-- Dropped last: the policies above must stop referencing them first.
drop function if exists public.owns_announcement_media(text);
drop function if exists public.can_post_announcements();

delete from public.schema_migrations where version = 51;

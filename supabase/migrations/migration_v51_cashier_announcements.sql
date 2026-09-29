-- ═══════════════════════════════════════════════════════════════════
-- Migration v51 — Main cashiers can post announcements
--
-- Until now only admins could write announcements (v36) and only admins
-- could see the whole board (v43). The client asked for main cashiers to
-- post too, so this migration widens the write side to `role = 'cashier'`
-- and draws the line at OWNERSHIP rather than role:
--
--   admin    — posts, edits and takes down anything, as before.
--   cashier  — posts; edits and takes down only what they posted.
--   everyone else — unchanged: the audience check, and nothing else.
--
-- Branch cashiers are deliberately NOT included. v43 settled that they are
-- an audience, not managers, and nothing about this request changes that.
--
-- ── Why ownership and not just role ────────────────────────────────
-- Two cashiers and an admin share one board. A cashier taking down the
-- admin's notice — by accident or otherwise — is the failure worth
-- designing against, and `created_by` (v36) already records who wrote
-- each row. Rows with a null `created_by` (posted before that column was
-- populated) belong to nobody, so only an admin can touch them.
--
-- ── Numbering ──────────────────────────────────────────────────────
-- v48–v50 are the delivery system, which is not applied to production and
-- is not shipping in 1.5.1. This migration touches only announcements
-- (v36/v43/v44 objects, all present on production at v47), so it applies
-- cleanly on its own and the ledger will read 47, 51 until delivery ships.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_cashier_announcements_v51.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Who may write announcements ─────────────────────────────────
-- Deliberately narrower than is_staff(): inventory and branch cashiers
-- are not authors. SECURITY DEFINER so it reads profiles regardless of
-- RLS, matching is_admin() / is_staff().
create or replace function public.can_post_announcements()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'cashier')
  );
$$;

-- Whether the current account may overwrite or remove a file in the
-- announcement bucket: nobody else's announcement points at it, and it is
-- not the birthday greeting (an admin-only setting). A file nothing points
-- at is an orphan, which any author may clear.
create or replace function public.owns_announcement_media(object_name text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    not exists (
      select 1 from public.announcements a
      where a.image_path = object_name
        and a.created_by is distinct from auth.uid()
    )
    and not exists (
      select 1 from public.app_config c
      where c.key = 'birthday_greeting_image'
        and c.value = object_name
    );
$$;

-- ── 2. Reading ─────────────────────────────────────────────────────
-- An author has to see their own drafts, their own archived rows, and the
-- notices already on the board so they do not post a duplicate — so the
-- v43 admin bypass becomes an AUTHOR bypass. Everyone else, branch
-- cashiers included, still goes through the audience check, which is the
-- part v43 existed to protect.
drop policy if exists "announcements_select" on public.announcements;
create policy "announcements_select" on public.announcements
  for select to authenticated
  using (
    public.can_post_announcements()
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

-- ── 3. Writing ─────────────────────────────────────────────────────
-- `created_by = auth.uid()` in the INSERT check stops a cashier posting
-- under someone else's name; repeating it in the UPDATE check stops them
-- handing a row over to (or taking one from) another account.
drop policy if exists "announcements_insert" on public.announcements;
create policy "announcements_insert" on public.announcements
  for insert to authenticated
  with check (
    public.is_admin()
    or (public.can_post_announcements() and created_by = auth.uid())
  );

drop policy if exists "announcements_update" on public.announcements;
create policy "announcements_update" on public.announcements
  for update to authenticated
  using (
    public.is_admin()
    or (public.can_post_announcements() and created_by = auth.uid())
  )
  with check (
    public.is_admin()
    or (public.can_post_announcements() and created_by = auth.uid())
  );

-- Still no DELETE policy, on purpose (v36). Archive instead.

-- ── 4. Posters ─────────────────────────────────────────────────────
-- A cashier who can post can attach a poster, so the bucket's write side
-- follows the same rule. Read is unchanged in substance: anyone may read
-- an object an announcement points at; the admin-only arm becomes
-- author-only so an author can also see a file before its row exists.
drop policy if exists "announcement-media read"   on storage.objects;
drop policy if exists "announcement-media write"  on storage.objects;
drop policy if exists "announcement-media update" on storage.objects;
drop policy if exists "announcement-media delete" on storage.objects;

create policy "announcement-media read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'announcement-media'
    and (
      public.can_post_announcements()
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
  with check (
    bucket_id = 'announcement-media'
    and public.can_post_announcements()
  );

-- Overwriting someone else's live poster would change their announcement
-- without touching the row the UPDATE policy protects, so the same
-- ownership rule is repeated here in file terms.
create policy "announcement-media update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'announcement-media'
    and public.can_post_announcements()
    and (public.is_admin() or public.owns_announcement_media(name))
  )
  with check (
    bucket_id = 'announcement-media'
    and public.can_post_announcements()
    and (public.is_admin() or public.owns_announcement_media(name))
  );

-- An orphaned image IS deletable (v44): replacing a poster should not
-- leave the old file paying for storage forever. A cashier may drop an
-- orphan or their own poster — never another author's, and never the
-- birthday greeting, which only an admin sets.
create policy "announcement-media delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'announcement-media'
    and public.can_post_announcements()
    and (public.is_admin() or public.owns_announcement_media(name))
  );

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (51, 'cashier_announcements')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Both helpers exist:
--      select proname from pg_proc
--       where proname in ('can_post_announcements','owns_announcement_media');
--    Expect 2 rows.
--
-- 2. Signed in as a CASHIER:
--      select count(*) from public.announcements;      -- the whole board
--      insert into public.announcements (title, body, audience, created_by)
--      values ('test','test','all', auth.uid());       -- succeeds
--      update public.announcements set title = 'nope'
--       where created_by is distinct from auth.uid();  -- 0 rows
--
-- 3. Signed in as a BRANCH CASHIER, unchanged from v43 — only 'all' and
--    'branches' rows come back, archived ones never do:
--      select id, title, audience from public.announcements order by id;

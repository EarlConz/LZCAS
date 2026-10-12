-- ═══════════════════════════════════════════════════════════════════
-- Migration v44 — Posters: announcements and birthday greetings may be
-- text, an image, or both.
--
-- Four things:
--   1. announcements.image_path — the storage object path, NOT a URL.
--   2. body becomes nullable, guarded so a row can never be empty.
--   3. A private 'announcement-media' bucket with policies that inherit
--      the announcement audience check.
--   4. app_config.birthday_greeting_image — one global poster, beside
--      the message that already lives there.
--
-- ── Why a path and not a URL ───────────────────────────────────────
-- The bucket is private, so the app displays these through a signed URL
-- that expires. Storing a URL would bake in an expiry that outlives its
-- own validity; storing the path lets the app re-sign on demand.
--
-- ── Why the bucket is private ──────────────────────────────────────
-- v39 made branches an announcement audience and v43 stopped branch
-- cashiers reading Members-only notices. A public bucket would hand the
-- poster for that same notice to anyone with the link, reopening the leak
-- one layer down. v8 made 'member-ids' private for the same reason.
--
-- The read policy below does NOT re-implement the audience rules. It asks
-- whether the caller can see an announcement carrying this path — and that
-- subquery runs under the caller's own RLS, so it inherits whatever
-- announcements_select decides, now and after any future change.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_announcement_images_v44.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. The column ──────────────────────────────────────────────────
alter table public.announcements
  add column if not exists image_path text;

-- ── 2. Body becomes optional, but not absent ───────────────────────
-- An image-only announcement has no body. It still needs a title: that is
-- the row label in the list, the header in the unseen popup, and the entry
-- in a member's saved list, none of which have an image to fall back on.
alter table public.announcements
  alter column body drop not null;

alter table public.announcements
  drop constraint if exists announcement_has_content;

alter table public.announcements
  add constraint announcement_has_content check (
    nullif(btrim(coalesce(body, '')), '') is not null
    or nullif(btrim(coalesce(image_path, '')), '') is not null
  );

-- ── 3. The bucket ──────────────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('announcement-media', 'announcement-media', false)
on conflict (id) do update set public = false;

drop policy if exists "announcement-media read"   on storage.objects;
drop policy if exists "announcement-media write"  on storage.objects;
drop policy if exists "announcement-media update" on storage.objects;
drop policy if exists "announcement-media delete" on storage.objects;

-- Read: admins always; everyone else only if some announcement they are
-- allowed to see points at this object. The birthday poster has no
-- announcement row, so it is matched through app_config instead.
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

-- Writes are admin-only, matching announcements_insert/update. A poster is
-- authored in the same screen as the notice it belongs to.
create policy "announcement-media write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'announcement-media' and public.is_admin());

create policy "announcement-media update" on storage.objects
  for update to authenticated
  using (bucket_id = 'announcement-media' and public.is_admin())
  with check (bucket_id = 'announcement-media' and public.is_admin());

-- Unlike announcements themselves, an orphaned image IS deletable: replacing
-- a poster should not leave the old file paying storage forever. The row it
-- belonged to keeps existing; only the file goes.
create policy "announcement-media delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'announcement-media' and public.is_admin());

-- ── 4. The birthday poster ─────────────────────────────────────────
-- Empty string means "no poster, text only" — the same shape the message
-- key already uses, so ConfigService needs no new absent/blank distinction.
insert into public.app_config (key, value)
values ('birthday_greeting_image', '')
on conflict (key) do nothing;

-- ── Verify ─────────────────────────────────────────────────────────
-- select
--   (select count(*) from information_schema.columns
--     where table_schema='public' and table_name='announcements'
--       and column_name='image_path')                          as has_column,
--   (select is_nullable from information_schema.columns
--     where table_schema='public' and table_name='announcements'
--       and column_name='body')                                as body_nullable,
--   (select public from storage.buckets
--     where id='announcement-media')                           as bucket_public,
--   (select count(*) from public.app_config
--     where key='birthday_greeting_image')                     as config_key;
-- Expect 1, YES, false, 1.
--
-- The guard holds (expect an error, not an inserted row):
--   insert into public.announcements (title, body) values ('empty', '   ');

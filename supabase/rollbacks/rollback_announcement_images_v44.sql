-- ═══════════════════════════════════════════════════════════════════
-- Rollback for migration_v44_announcement_images.sql
--
-- ⚠️ Read before running. This is lossy in two ways:
--
--   1. Dropping image_path discards which poster belonged to which
--      announcement. The FILES are left in the bucket (this script does
--      not delete them), but nothing records what they were for.
--   2. Restoring `body not null` FAILS if any image-only announcement
--      exists — those rows have a null body by design. The script stops
--      and tells you how many rather than inventing text for them.
--
-- The safe alternative, if the goal is just "stop showing posters", is to
-- leave the schema alone and clear the paths:
--
--   update public.announcements set image_path = null;
--   update public.app_config set value = '' where key = 'birthday_greeting_image';
--
-- That keeps every announcement readable and is reversible; this is not.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  imageonly integer;
begin
  select count(*) into imageonly
  from public.announcements
  where nullif(btrim(coalesce(body, '')), '') is null;

  if imageonly > 0 then
    raise exception
      'v44 rollback aborted: % announcement(s) have no body text and exist only as a poster. Restoring "body not null" would require deleting them or fabricating text. Give them a body first, or clear image_path instead of rolling back (see this script''s header).',
      imageonly;
  end if;
end $$;

alter table public.announcements
  drop constraint if exists announcement_has_content;

alter table public.announcements
  alter column body set not null;

alter table public.announcements
  drop column if exists image_path;

drop policy if exists "announcement-media read"   on storage.objects;
drop policy if exists "announcement-media write"  on storage.objects;
drop policy if exists "announcement-media update" on storage.objects;
drop policy if exists "announcement-media delete" on storage.objects;

-- The bucket itself is left in place. Dropping it would orphan its objects,
-- and storage.buckets refuses to drop a non-empty bucket anyway. Remove it
-- by hand from the Storage UI once you have confirmed nothing needs the
-- files.

delete from public.app_config where key = 'birthday_greeting_image';

-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration v36 — Announcements and birthday greetings
--
-- ⚠️ Parts 1 and 2 DESTROY CONTENT: every announcement ever posted, and
-- every member's saved list. Unlike the v35 rollback there is no way to
-- keep them "just in case" — the tables are the content.
--
-- Read them out first if there is any chance you want them back:
--   select * from public.announcements order by published_at desc;
--   select * from public.member_saved_items order by saved_at desc;
--
-- The safe alternative to rolling back is to archive everything, which
-- empties the members' screens without losing anything:
--   update public.announcements set archived_at = now() where archived_at is null;
-- and set birthday_greetings_enabled to 'false' (part 3 below).
-- ═══════════════════════════════════════════════════════════════════

-- ── 3. Turn the birthday greeting off (non-destructive, do this first) ──
update public.app_config set value = 'false'
  where key = 'birthday_greetings_enabled';

-- ── Everything below is destructive ────────────────────────────────

-- 2. Saved items. Dropped before announcements because of the FK.
drop table if exists public.member_saved_items;

-- 1. Announcements.
drop table if exists public.announcements;

-- Settings keys. Harmless to leave; remove only for a clean slate.
delete from public.app_config
  where key in ('birthday_greetings_enabled',
                'birthday_greeting_days',
                'birthday_greeting_message');

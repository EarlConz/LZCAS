-- ═══════════════════════════════════════════════════════════════════
-- Migration v36 — Announcements, saved items, and birthday greetings
--
-- Three things:
--   1. announcements  — admin-posted notices, targeted and time-limited.
--   2. member_saved_items — the per-member state that lets someone KEEP an
--      announcement (or a birthday greeting) past the point it would have
--      disappeared.
--   3. app_config keys driving the automatic birthday greeting.
--
-- ── Two decisions worth knowing before reading the policies ────────
--
-- ANNOUNCEMENTS ARE NEVER DELETED. There is deliberately no DELETE policy:
-- once a member can save one, deleting the row would reach into their saved
-- list and empty it. Taking a notice out of circulation sets archived_at.
-- The absence of a policy is the enforcement.
--
-- RLS DOES NOT FILTER BY ends_at. It filters archived_at and audience, but
-- an expired announcement stays READABLE — otherwise a member could not see
-- one they had saved. "Current" vs "saved" is a presentation split, made in
-- the app, not a visibility rule.
--
-- No scheduler anywhere. Birthday greetings are computed by the client from
-- members.birthday when the member opens the app; nothing runs on a timer
-- and nothing is sent.
--
-- Rollback: supabase/rollbacks/rollback_announcements_v36.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Announcements ───────────────────────────────────────────────
create table if not exists public.announcements (
  id           bigint generated always as identity primary key,
  title        text        not null,
  body         text        not null,
  -- Who it reaches. 'members' means plain members only — a reseller is not
  -- a member for this purpose, which is what makes the three values
  -- mutually exclusive rather than nested.
  audience     text        not null default 'all'
                 check (audience in ('all', 'resellers', 'members')),
  published_at timestamptz not null default now(),
  ends_at      timestamptz,          -- null = no end date, stays current
  archived_at  timestamptz,          -- null = in circulation
  created_by   uuid,
  created_at   timestamptz not null default now()
);

create index if not exists idx_announcements_live
  on public.announcements (published_at desc)
  where archived_at is null;

alter table public.announcements enable row level security;

-- Staff see every announcement, including archived ones, because they
-- manage them. Everyone else sees announcements that are in circulation,
-- already published, and addressed to their role.
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

drop policy if exists "announcements_insert" on public.announcements;
create policy "announcements_insert" on public.announcements
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "announcements_update" on public.announcements;
create policy "announcements_update" on public.announcements
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No DELETE policy on purpose — see the header. Archive instead.

-- ── 2. Saved items ─────────────────────────────────────────────────
-- One table for both kinds so the member's "Saved" list is a single query.
-- A birthday greeting is not a row anywhere — it is computed — so it is
-- identified by the YEAR it was given, which is enough to say "keep the
-- greeting I got in 2026".
create table if not exists public.member_saved_items (
  id              bigint generated always as identity primary key,
  member_id       bigint      not null,
  item_kind       text        not null
                    check (item_kind in ('announcement', 'birthday')),
  announcement_id bigint      references public.announcements(id) on delete cascade,
  birthday_year   integer,
  saved_at        timestamptz not null default now(),
  -- Exactly one of the two references, matching the kind. Without this a row
  -- could claim to be an announcement and carry a year.
  constraint saved_item_shape check (
    (item_kind = 'announcement'
       and announcement_id is not null and birthday_year is null)
    or (item_kind = 'birthday'
       and birthday_year is not null and announcement_id is null)
  )
);

-- Partial uniques rather than one composite: a plain UNIQUE over nullable
-- columns treats NULLs as distinct, so it would let the same item be saved
-- twice.
create unique index if not exists uq_saved_announcement
  on public.member_saved_items (member_id, announcement_id)
  where item_kind = 'announcement';

create unique index if not exists uq_saved_birthday
  on public.member_saved_items (member_id, birthday_year)
  where item_kind = 'birthday';

create index if not exists idx_saved_member
  on public.member_saved_items (member_id, saved_at desc);

alter table public.member_saved_items enable row level security;

-- Staff may READ these, so the admin screen can warn that N members have
-- saved a notice before it is archived. They may not write them: nobody
-- gets to star or unstar on someone else's behalf.
drop policy if exists "saved_items_select" on public.member_saved_items;
create policy "saved_items_select" on public.member_saved_items
  for select to authenticated
  using (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );

drop policy if exists "saved_items_insert" on public.member_saved_items;
create policy "saved_items_insert" on public.member_saved_items
  for insert to authenticated
  with check (
    exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );

drop policy if exists "saved_items_delete" on public.member_saved_items;
create policy "saved_items_delete" on public.member_saved_items
  for delete to authenticated
  using (
    exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = member_saved_items.member_id
    )
  );

-- ── 3. Birthday greeting settings ──────────────────────────────────
-- Kept in app_config so the wording and the window can change without a
-- rebuild. app_config has RLS disabled to match the rest of the app's
-- settings; these are not secrets.
insert into public.app_config (key, value) values
  ('birthday_greetings_enabled', 'true'),
  ('birthday_greeting_days',     '30'),
  ('birthday_greeting_message',
   'Everyone at GUTVita wishes you all the best for the year ahead. Thank you for being part of the team.')
on conflict (key) do nothing;

-- ── Verify ─────────────────────────────────────────────────────────
-- select
--   (select count(*) from information_schema.tables
--     where table_schema='public' and table_name='announcements')       as announcements,
--   (select count(*) from information_schema.tables
--     where table_schema='public' and table_name='member_saved_items')  as saved_items,
--   (select count(*) from public.app_config
--     where key like 'birthday_greeting%')                              as config_keys;
-- Expect 1, 1, 3.
--
-- Deletion really is blocked (run as an admin; expect 0 rows affected and
-- no error, because RLS filters rather than raising):
--   delete from public.announcements where id = <some id>;

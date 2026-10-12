-- ═══════════════════════════════════════════════════════════════════
-- Migration v45 — A record of which migrations have been applied
--
-- Until now nothing recorded what had been run. Answering "is v43 on this
-- database?" meant checking whether the objects it creates happen to exist
-- — archaeology, and it only works for migrations that leave a detectable
-- trace. A migration that redefines a function leaves none.
--
-- This adds the ledger, backfills it from what can be detected, and gives
-- every future migration a one-line footer to record itself.
--
-- ── Read this before trusting a row ────────────────────────────────
-- `verified` is the important column.
--
--   true  — positively detected, or recorded by the migration itself.
--   false — ASSUMED by the backfill below. The app could not run without
--           it, so it is almost certainly applied, but nothing here
--           proves it.
--
-- The distinction is the whole point: a ledger that quietly invents
-- history is worse than no ledger, because it gets believed.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_schema_migrations_ledger_v45.sql
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.schema_migrations (
  version    integer     primary key,
  name       text        not null,
  applied_at timestamptz not null default now(),
  -- Who ran it. In practice 'postgres' — everything here is pasted into
  -- the SQL editor — but it distinguishes that from a future CI runner.
  applied_by text        not null default current_user,
  verified   boolean     not null default true,
  note       text
);

comment on table public.schema_migrations is
  'One row per applied migration. verified=false means the v45 backfill '
  'assumed it rather than detecting it.';

alter table public.schema_migrations enable row level security;

-- Admins may read it; nobody may write it through the API. Migrations run
-- in the SQL editor as superuser, which bypasses RLS, so the absence of an
-- INSERT policy costs the migrations nothing and stops the app rewriting
-- its own history.
drop policy if exists "schema_migrations_select" on public.schema_migrations;
create policy "schema_migrations_select" on public.schema_migrations
  for select to authenticated
  using (public.is_admin());

-- ── Backfill ───────────────────────────────────────────────────────
-- Detection first, for everything that leaves a trace. This is what makes
-- the script correct on BOTH environments without being told which is
-- which: run it on prod and it records prod's state, run it on staging and
-- it records staging's.

do $$
declare
  -- version, name, and whether it is present
  rec record;
begin
  for rec in
    select * from (values
      (8,  'private_id_bucket',
           exists (select 1 from storage.buckets
                   where id = 'member-ids' and public = false)),
      (29, 'mobile_flag',
           exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'profiles'
                     and column_name = 'mobile_enabled')),
      (30, 'branch_stock',
           to_regclass('public.branch_stock') is not null),
      (33, 'branch_stock_rls',
           exists (select 1 from pg_policies
                   where schemaname = 'public' and tablename = 'branch_stock')),
      (34, 'earnings_sources',
           exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname = 'get_member_earnings_sources')),
      (35, 'admin_fund_adjustments',
           exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public'
                     and p.proname = 'admin_adjust_member_funds')),
      (36, 'announcements_and_birthdays',
           to_regclass('public.announcements') is not null),
      (37, 'cashier_location',
           exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'profiles'
                     and column_name = 'location_updated_at')),
      (38, 'member_cashier_stock',
           exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'member_branch_stock')),
      (39, 'announcement_audiences',
           exists (select 1 from pg_constraint
                   where conrelid = to_regclass('public.announcements')
                     and pg_get_constraintdef(oid) ilike '%branches%')),
      (40, 'announcement_reads',
           to_regclass('public.announcement_reads') is not null),
      (41, 'saved_items_by_profile',
           exists (select 1 from information_schema.columns
                   where table_schema = 'public'
                     and table_name = 'member_saved_items'
                     and column_name = 'profile_id')),
      (42, 'server_now',
           exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'server_now')),
      (43, 'announcement_staff_bypass',
           exists (select 1 from pg_policies
                   where schemaname = 'public' and tablename = 'announcements'
                     and policyname = 'announcements_select'
                     and qual ilike '%is_admin%' and qual not ilike '%is_staff%')),
      (44, 'announcement_images',
           exists (select 1 from information_schema.columns
                   where table_schema = 'public' and table_name = 'announcements'
                     and column_name = 'image_path'))
    ) as t(version, name, present)
  loop
    if rec.present then
      insert into public.schema_migrations (version, name, verified, note)
      values (rec.version, rec.name, true,
              'backfilled by v45 — detected')
      on conflict (version) do nothing;
    end if;
  end loop;
end $$;

-- Now the ones with no detectable trace: the earnings chain (v6, v19–v27)
-- and the small structural ones. Every one of these is a prerequisite for
-- the app running at all, so on any database serving this app they are
-- applied — but that is an inference, and it is recorded as one.
insert into public.schema_migrations (version, name, verified, note)
select v.version, v.name, false,
       'backfilled by v45 — ASSUMED, not detected. Predates the ledger.'
from (values
  (2,  'early_schema'),           (3,  'early_schema'),
  (4,  'early_schema'),           (5,  'upgrade_guard'),
  (6,  'earnings_rpc'),           (7,  'lock_reads'),
  (9,  'fix_member_identity'),    (10, 'early_schema'),
  (11, 'early_schema'),           (12, 'package_based_role'),
  (13, 'early_schema'),           (14, 'early_schema'),
  (15, 'early_schema'),           (16, 'early_schema'),
  (17, 'upgrade_bonus'),          (18, 'early_schema'),
  (19, 'group_sales_frozen'),     (20, 'referral_frozen'),
  (21, 'chairman_weekly'),        (22, 'chairman_per_referral'),
  (23, 'chairman_immediate'),     (24, 'chairman_ledger'),
  (25, 'availment_based'),        (26, 'upgrade_min_tier'),
  (27, 'chairman_min_tier'),      (28, 'is_staff_branch_cashier'),
  (31, 'branch_transfer_reports'),(32, 'branch_transfer_note')
) as v(version, name)
-- Only assume the ones BELOW the highest thing we actually detected. On a
-- database that stops at v34 this refuses to invent v35+; on one that has
-- never run any of this, it inserts nothing at all.
where v.version < coalesce(
  (select max(version) from public.schema_migrations where verified), 0)
on conflict (version) do nothing;

-- ── Record this migration itself ───────────────────────────────────
insert into public.schema_migrations (version, name)
values (45, 'schema_migrations_ledger')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ═══════════════════════════════════════════════════════════════════
-- FROM NOW ON: end every migration with this, adjusting the two values.
--
--   insert into public.schema_migrations (version, name)
--   values (46, 'what_it_does')
--   on conflict (version) do update
--     set applied_at = now(), applied_by = current_user, verified = true;
--
-- And every rollback with:
--
--   delete from public.schema_migrations where version = 46;
-- ═══════════════════════════════════════════════════════════════════

-- ── Verify ─────────────────────────────────────────────────────────
-- What this database has, and how much of it is actually known:
--   select version, name, verified, applied_at::date
--   from public.schema_migrations order by version;
--
-- The headline number — anything below this that is missing is a gap:
--   select max(version) as at_version,
--          count(*) filter (where verified)     as detected,
--          count(*) filter (where not verified) as assumed
--   from public.schema_migrations;

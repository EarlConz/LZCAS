-- ═══════════════════════════════════════════════════════════════════
-- Migration v37 — Cashier / Branch Cashier saved location
--
-- Adds four nullable columns to `profiles` so a cashier (or branch
-- cashier) can save their physical store/branch location:
--   latitude             double precision
--   longitude            double precision
--   address              text        (human-readable reverse-geocoded string)
--   location_updated_at  timestamptz (when the location was last set)
--
-- NOTE ON THE TIMESTAMP NAME. An earlier revision of this migration called
-- that column plain `updated_at`. On an accounts table that name reads as
-- "row last modified", so any future touch-trigger or a change to the
-- update-user edge function would quietly repoint it and the cashier's
-- "Last updated <date>" line would start reporting something else. The
-- rename block below fixes a database that got the old name, so this file
-- is still safe to re-run on staging.
--
-- A member's "Nearest Cashiers" map reads these columns (role IN
-- ('cashier','branch_cashier') AND latitude IS NOT NULL) and sorts by
-- straight-line distance. No routing is stored or computed server-side.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_cashier_location_v37.sql
-- ═══════════════════════════════════════════════════════════════════

alter table public.profiles add column if not exists latitude double precision;
alter table public.profiles add column if not exists longitude double precision;
alter table public.profiles add column if not exists address text;

-- Carry over a database that got the earlier, too-generic `updated_at`.
-- `profiles` has never had an `updated_at` for any other purpose (see
-- schema.sql), so this can only be the location timestamp.
do $$
begin
  if exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'profiles'
          and column_name = 'updated_at')
     and not exists (
        select 1 from information_schema.columns
        where table_schema = 'public' and table_name = 'profiles'
          and column_name = 'location_updated_at')
  then
    alter table public.profiles rename column updated_at to location_updated_at;
  end if;
end $$;

alter table public.profiles
  add column if not exists location_updated_at timestamptz;

-- Partial index so the member map query (role IN (...) AND latitude IS NOT
-- NULL) stays cheap even as profiles grows.
create index if not exists idx_profiles_cashier_location
  on public.profiles (role, latitude)
  where latitude is not null;

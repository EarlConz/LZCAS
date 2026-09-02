-- ═══════════════════════════════════════════════════════════════════
-- Migration v37 — Cashier / Branch Cashier saved location
--
-- Adds four nullable columns to `profiles` so a cashier (or branch
-- cashier) can save their physical store/branch location:
--   latitude    double precision
--   longitude   double precision
--   address     text           (human-readable reverse-geocoded string)
--   updated_at  timestamptz    (when the location was last set)
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
alter table public.profiles add column if not exists updated_at timestamptz;

-- Partial index so the member map query (role IN (...) AND latitude IS NOT
-- NULL) stays cheap even as profiles grows.
create index if not exists idx_profiles_cashier_location
  on public.profiles (role, latitude)
  where latitude is not null;

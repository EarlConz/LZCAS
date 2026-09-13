-- ═══════════════════════════════════════════════════════════════════
-- Migration v47 — Member saved location
--
-- Mirrors the cashier/branch-cashier location columns (v37) on the
-- `members` table so a Member (Buyer) can save their default location:
--   latitude             double precision
--   longitude            double precision
--   address              text        (already exists on `members`)
--   location_updated_at  timestamptz (when the location was last set)
--
-- `address` already existed as the member's home/mailing address; it is
-- reused here exactly as `profiles.address` is reused for cashiers — the
-- saved location's reverse-geocoded string. All four columns are nullable
-- so existing member rows without a location keep working unchanged.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_member_location_v47.sql
-- ═══════════════════════════════════════════════════════════════════

alter table public.members add column if not exists latitude double precision;
alter table public.members add column if not exists longitude double precision;
alter table public.members add column if not exists location_updated_at timestamptz;

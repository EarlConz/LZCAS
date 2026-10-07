-- migration_v29_branch_cashier_mobile_flag.sql
-- ---------------------------------------------------------------------------
-- Per-account "mobile login allowed" flag for BRANCH CASHIER accounts.
--
-- Rule (client requirement):
--   * Branch-cashier accounts are DESKTOP-ONLY by default.
--   * An admin flips `mobile_enabled = true` on a specific account to permit
--     that person to log in on a phone/tablet.
--   * Cashier and inventory accounts remain desktop-only and IGNORE this flag.
--   * Admin / member / reseller may always use mobile (flag irrelevant).
--
-- Enforcement is in the app (RouteGuard + AuthState) — same posture as the
-- existing desktop-only gate. This column just carries the admin's decision.
--
-- Safe to re-run. Additive and reversible (see rollbacks/rollback_mobile_flag_v29.sql).
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists mobile_enabled boolean not null default false;

comment on column public.profiles.mobile_enabled is
  'Admin-controlled: when true, a branch_cashier account may log in on mobile. '
  'Ignored for other roles. Default false = desktop-only.';

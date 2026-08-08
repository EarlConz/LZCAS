-- rollback_mobile_flag_v29.sql
-- Reverts migration_v29_branch_cashier_mobile_flag.sql.
-- Drops the per-account mobile-login flag. After this, branch-cashier accounts
-- fall back to the app's default desktop-only behavior for that role.

alter table public.profiles
  drop column if exists mobile_enabled;

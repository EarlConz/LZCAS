-- ═══════════════════════════════════════════════════════════════════
-- Rollback v71 — STAGING ONLY.
--
-- ⛔ Never on production: production had these triggers before v71, and
-- removing them stops every Group Sales and referral payment.
--
-- Removes the four triggers v71 put on sales. The functions stay: unused
-- without the triggers, and the app's package upgrade still needs
-- process_package_upgrade.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists trg_sync_group_sales_ins on public.sales;
drop trigger if exists trg_sync_group_sales_upd on public.sales;
drop trigger if exists trg_remove_group_sales_del on public.sales;
drop trigger if exists trg_crystallize_referral_on_availment on public.sales;

delete from public.schema_migrations where version = 71;

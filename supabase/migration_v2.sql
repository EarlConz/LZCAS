-- ═══════════════════════════════════════════════════════════════════
-- Migration v2 — Passive income & upgrade referral bonus columns
-- Safe to run on existing databases (uses IF NOT EXISTS).
-- ═══════════════════════════════════════════════════════════════════

-- 1. Upgrade Referral Bonus on packages table
alter table public.packages
  add column if not exists upgrade_referral_bonus integer not null default 0;

-- 2. Passive Income column on earnings_history table
alter table public.earnings_history
  add column if not exists passive_income integer not null default 0;

-- ═══════════════════════════════════════════════════════════════════
-- DEPLOYMENT RESET — wipe test data, keep production configuration.
--
-- ⚠ DESTRUCTIVE AND IRREVERSIBLE. Review each section before running.
--
-- KEEPS (business configuration):
--   • packages          (membership tiers + bonus rates)
--   • categories        (product categories + commission rates)
--   • app_config        (app settings)
--   • staff accounts    (profiles WITHOUT member_id + their auth users)
--   • all schema: tables, columns, RLS policies, triggers, indexes
--
-- DELETES (test/transactional data):
--   • members (incl. soft-deleted), sales, member_transactions,
--     stock_movements, pending_requests, earnings_history,
--     withdrawal_requests
--   • member login accounts (profiles WITH member_id + auth users)
--   • the leftover borrows_archive table
--
-- OPTIONAL (commented out — decide per section):
--   • items (product inventory) — keep if your item list is real
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Wipe transactional/test data and reset ID counters ─────────
-- One statement so FK ordering never matters.
truncate table
  public.sales,
  public.member_transactions,
  public.stock_movements,
  public.pending_requests,
  public.earnings_history,
  public.withdrawal_requests,
  public.members
restart identity;

-- ── 2. OPTIONAL: wipe the product inventory too ────────────────────
-- Uncomment ONLY if your items list is test data. If your real product
-- catalog is already entered, leave this commented to keep it.
-- truncate table public.items restart identity;

-- ── 3. Delete member LOGIN accounts (keeps staff accounts) ─────────
-- Member accounts are the profiles rows linked to a member via
-- member_id; staff (admin/cashier/inventory) profiles have no
-- member_id and are kept.
delete from auth.users
  where id in (
    select id from public.profiles where member_id is not null
  );
delete from public.profiles where member_id is not null;

-- ── 4. Drop the leftover archive from the old borrow system ────────
drop table if exists public.borrows_archive cascade;

-- ── 5. Verification — run after the above ──────────────────────────
select
  (select count(*) from public.members)              as members,
  (select count(*) from public.sales)                as sales,
  (select count(*) from public.member_transactions)  as member_transactions,
  (select count(*) from public.stock_movements)      as stock_movements,
  (select count(*) from public.pending_requests)     as pending_requests,
  (select count(*) from public.earnings_history)     as earnings_history,
  (select count(*) from public.withdrawal_requests)  as withdrawal_requests,
  (select count(*) from public.items)                as items_kept,
  (select count(*) from public.packages)             as packages_kept,
  (select count(*) from public.categories)           as categories_kept,
  (select count(*) from public.profiles)             as staff_accounts_kept;
-- Expect: all left-hand counts 0 (items 0 only if you ran section 2);
-- packages/categories/staff unchanged.

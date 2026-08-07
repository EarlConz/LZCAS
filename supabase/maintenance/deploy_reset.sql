-- ═══════════════════════════════════════════════════════════════════
-- DEPLOYMENT RESET — wipe test data, keep production configuration.
--
-- ⚠ DESTRUCTIVE AND IRREVERSIBLE. Review each section before running.
--
-- KEEPS (business configuration):
--   • packages          (membership tiers + bonus rates)
--   • categories        (product categories + per-category low-stock
--                        thresholds + commission rates)
--   • app_config        (app settings)
--   • staff accounts    (profiles WITHOUT member_id + their auth users)
--   • all schema: tables, columns, views, RPCs, RLS policies, triggers
--
-- DELETES (test/transactional data):
--   • members (incl. soft-deleted), sales, member_transactions,
--     stock_movements, pending_requests, earnings_history,
--     withdrawal_requests
--   • member login accounts (profiles WITH member_id + their auth users)
--   • the leftover borrows_archive table
--
-- OPTIONAL (commented out — decide per section):
--   • items (product inventory) — keep if your item list is real
--
-- FK NOTE: public.profiles.member_id references public.members(id). Because
-- of that constraint, `members` CANNOT be TRUNCATEd on its own (Postgres
-- blocks truncating any table referenced by a foreign key). So we first
-- delete the member-linked profiles, then clear `members` with DELETE +
-- an identity restart. This works whether or not the FK is enforced on
-- your instance.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Delete member LOGIN accounts first (keeps staff accounts) ───
-- Member accounts are the profiles rows linked to a member via member_id;
-- staff (admin/cashier/inventory) profiles have no member_id and are kept.
-- Done BEFORE clearing members so nothing still references them.
delete from auth.users
  where id in (
    select id from public.profiles where member_id is not null
  );
delete from public.profiles where member_id is not null;

-- ── 2. Wipe transactional/test data and reset ID counters ─────────
-- None of these are referenced by a kept table, so TRUNCATE is safe here.
truncate table
  public.sales,
  public.member_transactions,
  public.stock_movements,
  public.pending_requests,
  public.earnings_history,
  public.withdrawal_requests
restart identity;

-- ── 3. Clear members (DELETE, not TRUNCATE — see FK NOTE) ──────────
-- Referencing profiles were removed in section 1, so this succeeds; the
-- identity restart mimics TRUNCATE ... RESTART IDENTITY so new members
-- start from id 1 again.
delete from public.members;
alter table public.members alter column id restart with 1;

-- ── 4. OPTIONAL: wipe the product inventory too ────────────────────
-- Uncomment ONLY if your items list is test data. If your real product
-- catalog is already entered, leave this commented to keep it.
-- truncate table public.items restart identity;

-- ── 5. Drop the leftover archive from the old borrow system ────────
drop table if exists public.borrows_archive cascade;

-- ── 6. Verification — run after the above ──────────────────────────
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
-- Expect: all left-hand counts 0 (items 0 only if you ran section 4);
-- packages/categories/staff unchanged.

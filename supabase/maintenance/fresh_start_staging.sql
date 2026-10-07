-- ═══════════════════════════════════════════════════════════════════
-- STAGING ONLY — a fresh start for the client's testing (2026-10-08)
--
-- Clears everything the team's testing left behind, so the client starts
-- clean on the staging APK and exe.
--
-- KEPT
--   • members and their logins, with their package and referrer
--     (their balances start at zero: the activity that made them goes)
--   • every staff account: admins, cashiers, branch cashiers, riders,
--     and their saved locations and push tokens
--   • packages, categories, app_config (settings), schema_migrations
--
-- DELETED (and their ID counters restarted)
--   • products: items, branch_stock, stock_movements, stock_transfers
--   • sales, member_transactions (earnings, commissions, funds),
--     fund_adjustments, earnings_history
--   • withdrawal_requests, pending_requests (deletion, stock and
--     borrow requests)
--   • delivery orders: orders, order_items, order_fee_offers
--   • announcements, announcement_reads, member_saved_items
--
-- NOT TOUCHED: files in Storage (product pictures, announcement posters,
-- member ID images). Rows that pointed at them are gone; empty the
-- product-images and announcement-media buckets from the dashboard
-- (Storage) if wanted. Supabase does not allow deleting them from SQL.
--
-- Guard: runs only where the Vault entry order_push_url names the staging
-- project (sisyujbpcueifeonnzfw). Production has its own URL, so it stops
-- there even after production gets the delivery migrations.
--
-- Run the whole file at once in the STAGING SQL editor. It is one
-- transaction: any error undoes all of it. The last query shows what is
-- left.
-- ═══════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_url    text;
  v_tables text[] := array[
    -- delivery
    'order_fee_offers', 'order_items', 'orders',
    -- money and earnings
    'member_transactions', 'fund_adjustments', 'earnings_history',
    'withdrawal_requests',
    -- requests
    'pending_requests',
    -- sales and products
    'sales', 'stock_movements', 'stock_transfers', 'branch_stock', 'items',
    -- announcements
    'announcement_reads', 'member_saved_items', 'announcements'
  ];
  v_found  text[] := '{}';
  t        text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'order_push_url';
  if v_url is null or position('sisyujbpcueifeonnzfw' in v_url) = 0 then
    raise exception 'Refused: this is not the staging project (order_push_url does not name sisyujbpcueifeonnzfw).';
  end if;

  foreach t in array v_tables loop
    if to_regclass('public.' || t) is not null then
      v_found := v_found || ('public.' || t);
    end if;
  end loop;

  -- One statement, no CASCADE: if a kept table depended on one of these,
  -- Postgres refuses and nothing is deleted.
  execute 'truncate table ' || array_to_string(v_found, ', ') || ' restart identity';
end;
$$;

commit;

-- ── What is left ───────────────────────────────────────────────────
-- Expect 0 in every "cleared" column; the "kept" columns are what the
-- client starts with.
select
  (select count(*) from public.members where not is_deleted)        as kept_members,
  (select count(*) from public.profiles where member_id is null)    as kept_staff_accounts,
  (select count(*) from public.packages)                            as kept_packages,
  (select count(*) from public.categories)                          as kept_categories,
  (select count(*) from public.items)                               as cleared_products,
  (select count(*) from public.sales)                               as cleared_sales,
  (select count(*) from public.member_transactions)                 as cleared_transactions,
  (select count(*) from public.withdrawal_requests)                 as cleared_withdrawals,
  (select count(*) from public.pending_requests)                    as cleared_requests,
  (select count(*) from public.orders)                              as cleared_orders,
  (select count(*) from public.announcements)                       as cleared_announcements;

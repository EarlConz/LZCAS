-- ═══════════════════════════════════════════════════════════════════
-- STAGING ONLY — wipe every delivery order and everything it caused
--
-- Leaves staging as if no delivery order had ever been placed:
--   1. stock: the items orders took off the shelf go back on it
--      (orders whose stock left: sale recorded, or shipped by courier and
--      not returned). Status is recomputed with the same thresholds as
--      the app (category, else app_config, else 50);
--   2. sales: the rows order_record_sales wrote (matched on buyer, item
--      and the exact sales_recorded_at timestamp). Deleting them fires
--      v19's trg_remove_group_sales_del, which removes the Group Sales
--      commissions they paid;
--   3. funds: every "Order Payment (Balance|Earnings) …" member
--      transaction — payments and their refunds — so balances return to
--      what they were before ordering;
--   4. the orders themselves, their lines and fee offers.
--
-- Kept: members, rider and staff accounts, rider positions, push tokens,
-- withdrawals, POS sales, and every other transaction.
--
-- Not covered: orders completed before v52 (when the app, not the
-- database, wrote the sale). Their sales cannot be told apart from POS
-- sales. The notice at the start says how many there are; expect 0.
--
-- Guard: refuses to run unless migration v61 is recorded. Production has
-- no delivery migrations at all, so it stops there.
--
-- Run the whole file at once in the staging SQL editor. It is one
-- transaction: any error undoes all of it.
-- ═══════════════════════════════════════════════════════════════════

begin;

do $$
declare
  v_orders  int;
  v_sold    int;
  v_sales   int;
  v_txns    int;
  v_legacy  int;
begin
  if not exists (select 1 from public.schema_migrations where version = 61) then
    raise exception 'Refused: migration v61 is not recorded here. This script is for staging only.';
  end if;

  select count(*) into v_orders from public.orders;
  select count(*) into v_sold
    from public.orders
   where sales_recorded_at is not null or stock_taken_at is not null;
  select count(*) into v_sales
    from public.sales s
    join public.orders o
      on o.sales_recorded_at is not null
     and s.timestamp = o.sales_recorded_at
     and s.buyer_id  = o.member_id
     and s.item_id in (select product_id from public.order_items where order_id = o.id);
  select count(*) into v_txns
    from public.member_transactions
   where item_name like 'Order Payment (%';
  select count(*) into v_legacy
    from public.orders
   where status = 'Completed' and sales_recorded_at is null;

  raise notice 'Wiping % orders (% took stock), % sales rows, % order payment/refund transactions. Completed before v52, sales left alone: %.',
    v_orders, v_sold, v_sales, v_txns, v_legacy;
end $$;

-- ── 1. Stock back on the shelf ─────────────────────────────────────
with taken as (
  select oi.product_id, sum(oi.quantity)::int as qty
    from public.order_items oi
    join public.orders o on o.id = oi.order_id
   where o.sales_recorded_at is not null or o.stock_taken_at is not null
   group by oi.product_id
)
update public.items i
   set stock        = i.stock + t.qty,
       last_updated = now()
  from taken t
 where i.id = t.product_id;

update public.items i
   set status = case
                  when i.stock <= 0 then 'Out of Stock'
                  when i.stock < coalesce(
                         (select c.low_stock_threshold from public.categories c
                           where c.name = i.category),
                         (select value::int from public.app_config
                           where key = 'low_stock_threshold'),
                         50) then 'Low Stock'
                  else 'Good'
                end
 where i.id in (
   select oi.product_id
     from public.order_items oi
     join public.orders o on o.id = oi.order_id
    where o.sales_recorded_at is not null or o.stock_taken_at is not null
 );

-- ── 2. The sales they recorded (and, by trigger, their commissions) ─
delete from public.sales s
 using public.orders o
 where o.sales_recorded_at is not null
   and s.timestamp = o.sales_recorded_at
   and s.buyer_id  = o.member_id
   and s.item_id in (select product_id from public.order_items where order_id = o.id);

-- ── 3. Order payments and refunds in members' funds ────────────────
delete from public.member_transactions
 where item_name like 'Order Payment (%';

-- ── 4. The orders ──────────────────────────────────────────────────
delete from public.order_fee_offers;
delete from public.order_items;
delete from public.orders;

-- ── Check (expect zeros) ───────────────────────────────────────────
select
  (select count(*) from public.orders)              as orders_left,
  (select count(*) from public.order_items)         as order_items_left,
  (select count(*) from public.order_fee_offers)    as fee_offers_left,
  (select count(*) from public.member_transactions
    where item_name like 'Order Payment (%')        as order_payments_left;

commit;

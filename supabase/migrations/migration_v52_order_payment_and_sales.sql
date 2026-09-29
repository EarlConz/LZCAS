-- ═══════════════════════════════════════════════════════════════════
-- Migration v52 — Payment, and the sale the member's confirmation
--                 never recorded
--
-- Closes the gap v50 left open (see its header, and
-- docs/delivery_system_plan.md §7): an order the MEMBER confirms is
-- never written to `sales` and never decrements stock. Today only the
-- cashier's counter path records the sale, and it does so CLIENT-side
-- in delivery_orders_page._completeSale. A member tapping "I received
-- this" completes an order that the business has no record of selling.
--
-- Requires v49 (caller checks, my_member_id(), is_delivery()) and v50
-- (the rider states and the payment columns).
--
-- ── What this migration decides ────────────────────────────────────
--
-- 1. SALE RECORDING MOVES SERVER-SIDE, into order_record_sales(), which
--    every completion path calls. It writes one `sales` row per line
--    and decrements `items.stock`, recomputing `status` with the same
--    effective threshold the `items_with_status` view uses (v10), so
--    the inventory list does not disagree with itself.
--
--    *** THE APP MUST STOP DOING THIS ***
--    delivery_orders_page._completeSale currently writes `sales` and
--    updates `items` before calling complete_delivery_order. Ship this
--    migration with the build that removes that loop, or every counter
--    handover records the sale twice and decrements stock twice.
--    `orders.sales_recorded_at` makes the RPC side idempotent; it
--    cannot defend against a client writing its own rows.
--
-- 2. PAYMENT BY FUNDS inserts ONE NEGATIVE member_transactions row,
--    append-only, exactly as v35's admin adjustments do. Nothing is
--    ever updated or deleted; the ledger stays the history.
--
-- 3. get_member_earnings IS REDEFINED. This is the part the plan did
--    not account for and it matters: that function sums
--    member_transactions by SPECIFIC item_name prefixes ('Direct
--    Referral%', 'Group Sales%', …). A row with a new prefix is not
--    subtracted — it is IGNORED. Writing a negative "Order Payment"
--    row without this change would take the money on the order and
--    leave the member's balance untouched. The two new prefixes are
--    'Order Payment (Balance)%' and 'Order Payment (Earnings)%',
--    one per source bucket, because the bucket has to survive in the
--    ledger for the sums to stay separable.
--
--    Everything else about the function is unchanged, including the
--    greatest(0, …) clamps and the approved-withdrawal subtraction.
--
-- 4. THE CoD NONCE IS CREATED ON DEMAND, by member_order_cod_code(),
--    not at the moment an order becomes Agreed. The plan put it at
--    Agreed, which would mean redefining both
--    member_respond_delivery_order and cashier_resolve_delivery_order
--    and reproducing v49's caller checks inside them — two rewrites of
--    working authorization code to set one column. Lazy creation gets
--    the same single-use guarantee with none of that risk, and an
--    order that never goes CoD never gets a nonce.
--
-- ── Known carry-over, deliberately not changed here ────────────────
-- The DELIVERY FEE is still not recorded in `sales`. It is not today
-- either — the client loop only ever wrote item lines — so this
-- migration preserves that behaviour rather than quietly altering what
-- revenue reports mean. Worth a decision of its own.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_order_payment_and_sales_v52.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Columns ─────────────────────────────────────────────────────
alter table public.orders
  add column if not exists paid_at                timestamptz,
  add column if not exists payment_transaction_id bigint,
  add column if not exists cod_nonce              text,
  add column if not exists sales_recorded_at      timestamptz,
  add column if not exists cod_remitted_at        timestamptz,
  add column if not exists cod_remitted_to        uuid;

-- One live nonce per order, and never the same code on two orders.
create unique index if not exists uq_orders_cod_nonce
  on public.orders (cod_nonce) where cod_nonce is not null;

-- Lets reports split cash from funds without joining back to `orders`,
-- and keeps a sale readable on its own — the rest of the table already
-- snapshots names rather than trusting foreign keys.
alter table public.sales
  add column if not exists payment_method text;

-- ── 2. Recording the sale ──────────────────────────────────────────
-- Internal: every caller below has already authorized itself. Not
-- granted to `authenticated` on purpose — nothing outside this file
-- should be able to conjure sales rows.
create or replace function public.order_record_sales(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order   public.orders%rowtype;
  v_line    record;
  v_name    text;
  v_stock   int;
  v_thresh  int;
  v_buyer   text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  -- Idempotent. Three completion paths reach this, and a retry after a
  -- dropped connection must not sell the same goods twice.
  if v_order.sales_recorded_at is not null then
    return;
  end if;

  select nullif(trim(coalesce(first_name, '') || ' ' || coalesce(last_name, '')), '')
    into v_buyer
    from public.members
   where id = v_order.member_id;

  for v_line in
    select product_id, quantity, unit_price
      from public.order_items
     where order_id = p_order_id
     order by id
  loop
    select i.name,
           i.stock,
           coalesce(
             c.low_stock_threshold,
             (select value::int from public.app_config
               where key = 'low_stock_threshold'),
             50
           )
      into v_name, v_stock, v_thresh
      from public.items i
      left join public.categories c on c.name = i.category
     where i.id = v_line.product_id;

    -- A product deleted between order and handover still sells: the
    -- sale is what happened. Only the stock update is skipped.
    if v_name is not null then
      v_stock := greatest(0, v_stock - v_line.quantity);
      update public.items
         set stock        = v_stock,
             status       = case
                              when v_stock <= 0        then 'Out of Stock'
                              when v_stock <  v_thresh then 'Low Stock'
                              else 'Good'
                            end,
             last_updated = now()
       where id = v_line.product_id;
    end if;

    insert into public.sales
      (user_id, item_id, item_name, quantity, price,
       buyer_id, buyer_name, timestamp, payment_method)
    values
      (coalesce(v_order.cashier_id, auth.uid()),
       v_line.product_id,
       coalesce(v_name, 'Item #' || v_line.product_id),
       v_line.quantity,
       -- sales.price is an integer; order lines are numeric.
       coalesce(round(v_line.unit_price)::int, 0),
       v_order.member_id,
       v_buyer,
       now(),
       v_order.payment_method);
  end loop;

  update public.orders
     set sales_recorded_at = now()
   where id = p_order_id;
end;
$$;

-- ── 3. Completion paths now record the sale ────────────────────────
-- Bodies are v50's, unchanged except for the order_record_sales() call
-- placed AFTER the status write, so a failure to record cannot leave an
-- order marked Completed by a transaction that then rolls back.

create or replace function public.member_confirm_received(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_member bigint;
begin
  select status, member_id into v_status, v_member
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_member <> public.my_member_id() then
    raise exception 'Not authorized: this is not your order';
  end if;
  if v_status <> 'Delivered' then
    raise exception 'Nothing to confirm yet (status "%")', v_status;
  end if;

  update public.orders
     set status              = 'Completed',
         confirmed_by        = auth.uid(),
         confirmed_at        = now(),
         confirmation_method = 'member_tap'
   where id = p_order_id;

  perform public.order_record_sales(p_order_id);
end;
$$;

create or replace function public.complete_delivery_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_owner  uuid;
begin
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required';
  end if;
  select status, cashier_id into v_status, v_owner
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;

  if v_status = 'Agreed' then
    update public.orders set status = 'Completed' where id = p_order_id;
  elsif v_status = 'Delivered' then
    update public.orders
       set status              = 'Completed',
           confirmed_by        = auth.uid(),
           confirmed_at        = now(),
           confirmation_method = 'cashier_override'
     where id = p_order_id;
  else
    raise exception 'Cannot complete an order in status "%"', v_status;
  end if;

  perform public.order_record_sales(p_order_id);
end;
$$;

-- ── 4. Payment by funds ────────────────────────────────────────────
create or replace function public.pay_order_with_funds(
  p_order_id      uuid,
  p_source_bucket text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     public.orders%rowtype;
  v_earnings  jsonb;
  v_available numeric;
  v_label     text;
  v_txn       bigint;
begin
  if p_source_bucket not in ('total_earnings', 'balance') then
    raise exception 'Unknown source bucket "%"', p_source_bucket;
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.member_id <> public.my_member_id() then
    raise exception 'Not authorized: this is not your order';
  end if;
  if v_order.status <> 'Agreed' then
    raise exception
      'An order can only be paid once both sides have agreed (status "%")',
      v_order.status;
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;
  if coalesce(v_order.final_total, 0) <= 0 then
    raise exception 'This order has no agreed total to pay';
  end if;

  -- The same figures the member sees on their own earnings screen:
  -- already net of approved withdrawals and of earlier order payments.
  v_earnings  := public.get_member_earnings(v_order.member_id);
  v_available := (v_earnings ->> (case
                                    when p_source_bucket = 'balance'
                                      then 'balance'
                                    else 'totalEarnings'
                                  end))::numeric;

  if v_available < v_order.final_total then
    raise exception
      'Not enough funds: % available in %, % needed',
      v_available,
      case when p_source_bucket = 'balance' then 'Balance' else 'Total Earnings' end,
      v_order.final_total;
  end if;

  -- Append-only, and prefixed so get_member_earnings (redefined below)
  -- subtracts it from the bucket it was taken from.
  v_label := case
               when p_source_bucket = 'balance'
                 then 'Order Payment (Balance)'
               else 'Order Payment (Earnings)'
             end
             || ' — Order #' || left(p_order_id::text, 8);

  insert into public.member_transactions
    (user_id, member_id, sale_id, item_id, item_name, quantity, price, timestamp)
  values
    (auth.uid(), v_order.member_id, null, null, v_label, 1,
     -round(v_order.final_total)::int, now())
  returning id into v_txn;

  update public.orders
     set payment_method         = 'funds',
         payment_status         = 'paid',
         paid_at                = now(),
         payment_transaction_id = v_txn
   where id = p_order_id;
end;
$$;

-- ── 5. Cash on delivery ────────────────────────────────────────────
-- The member asks for their own order's code; the app renders it as a
-- QR. Single-use, per-order, and NOT members.qr — that one is a
-- persistent identifier printed on things, so anyone who had ever seen
-- it could confirm someone else's delivery.
create or replace function public.member_order_cod_code(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.member_id <> public.my_member_id() then
    raise exception 'Not authorized: this is not your order';
  end if;
  if v_order.status not in ('Agreed', 'Assigned', 'Picked Up') then
    raise exception 'No code to show for an order in status "%"', v_order.status;
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;

  if v_order.cod_nonce is null then
    -- gen_random_uuid(), not pgcrypto's gen_random_bytes(): this
    -- function pins search_path to public, and on Supabase pgcrypto
    -- lives in `extensions`, so that call would not resolve. v4 UUIDs
    -- are random, and 32 hex characters is ample for a single-use code
    -- that is only ever valid for one order in one status window.
    update public.orders
       set cod_nonce      = replace(gen_random_uuid()::text, '-', ''),
           payment_method = 'cod'
     where id = p_order_id
    returning cod_nonce into v_order.cod_nonce;
  end if;

  return v_order.cod_nonce;
end;
$$;

-- One scan is the receipt confirmation AND the payment record. The
-- member has to be physically present with their phone, which is the
-- whole point of the gesture.
create or replace function public.confirm_cod_delivery(
  p_order_id uuid,
  p_nonce    text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_delivery() then
    raise exception 'Not authorized: delivery role required';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.delivery_id is distinct from auth.uid() then
    raise exception 'Not authorized: this delivery is not assigned to you';
  end if;
  if v_order.status not in ('Picked Up', 'Delivered') then
    raise exception 'Cannot confirm an order in status "%"', v_order.status;
  end if;
  -- Compared after the status check so a used code cannot be told apart
  -- from a wrong one by the error it produces.
  if v_order.cod_nonce is null or v_order.cod_nonce is distinct from p_nonce then
    raise exception 'That code is not valid for this order';
  end if;

  update public.orders
     set status              = 'Completed',
         delivered_at        = coalesce(delivered_at, now()),
         confirmed_by        = auth.uid(),
         confirmed_at        = now(),
         confirmation_method = 'qr',
         payment_method      = 'cod',
         payment_status      = 'paid',
         paid_at             = now(),
         cod_nonce           = null   -- single use, burnt on success
   where id = p_order_id;

  perform public.order_record_sales(p_order_id);
end;
$$;

-- The rider hands the cash to a cashier. Recorded so §8's "collected
-- vs remitted" tally has something to count; it settles no balances.
create or replace function public.cashier_remit_cod(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.payment_method is distinct from 'cod'
     or v_order.payment_status is distinct from 'paid' then
    raise exception 'This order has no collected cash to remit';
  end if;
  if v_order.cod_remitted_at is not null then
    raise exception 'This order was already remitted';
  end if;

  update public.orders
     set cod_remitted_at = now(),
         cod_remitted_to = auth.uid()
   where id = p_order_id;
end;
$$;

-- ── 6. Earnings, net of order payments ─────────────────────────────
-- v24's function, with two sums added and nothing else changed. The
-- clamps and the withdrawal subtraction are kept exactly as they were.
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_balance     integer := 0;
  v_indirect    integer := 0;
  v_passive     integer := 0;
  v_chairman    integer := 0;
  v_fridays     integer := 0;
  v_upgrade     integer := 0;
  v_total       integer := 0;
  v_earn_deduct integer := 0;
  v_bal_deduct  integer := 0;
  v_pay_bal     integer := 0;
  v_pay_earn    integer := 0;
begin
  -- ── Authorization: staff, or the member themselves ──────────────
  if not (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = p_member_id
    )
  ) then
    raise exception 'Not authorized to view these earnings';
  end if;

  select coalesce(sum(price), 0) into v_balance
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Direct Referral%';

  select coalesce(sum(price), 0) into v_indirect
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Indirect Referral%';

  select coalesce(sum(price), 0) into v_passive
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Group Sales%';

  select coalesce(sum(price), 0) into v_upgrade
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Upgrade Bonus%';

  select coalesce(sum(price), 0) into v_chairman
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Chairman Bonus%';

  -- NEW (v52): delivery orders paid from funds. These rows are stored
  -- NEGATIVE, so they are ADDED, not subtracted — the sign already
  -- says what they are, and a double negative here would silently pay
  -- the member for shopping.
  select coalesce(sum(price), 0) into v_pay_bal
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Order Payment (Balance)%';

  select coalesce(sum(price), 0) into v_pay_earn
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Order Payment (Earnings)%';

  v_fridays := 0;
  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

  select
    coalesce(sum(case when source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct
    from public.withdrawal_requests
    where member_id = p_member_id and status = 'approved';

  return jsonb_build_object(
    'totalEarnings',  greatest(0, v_total   + v_pay_earn - v_earn_deduct),
    'balance',        greatest(0, v_balance + v_pay_bal  - v_bal_deduct),
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$function$;

-- ── 7. Grants ──────────────────────────────────────────────────────
-- order_record_sales is deliberately absent: it is internal.
revoke all on function public.pay_order_with_funds(uuid, text) from public;
revoke all on function public.member_order_cod_code(uuid) from public;
revoke all on function public.confirm_cod_delivery(uuid, text) from public;
revoke all on function public.cashier_remit_cod(uuid) from public;
revoke all on function public.order_record_sales(uuid) from public;

grant execute on function public.pay_order_with_funds(uuid, text) to authenticated;
grant execute on function public.member_order_cod_code(uuid) to authenticated;
grant execute on function public.confirm_cod_delivery(uuid, text) to authenticated;
grant execute on function public.cashier_remit_cod(uuid) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (52, 'order_payment_and_sales')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Columns and functions exist:
--      select column_name from information_schema.columns
--       where table_schema='public' and table_name='orders'
--         and column_name in ('paid_at','cod_nonce','sales_recorded_at',
--                             'cod_remitted_at')  order by 1;   -- expect 4
--      select proname from pg_proc
--       where proname in ('pay_order_with_funds','member_order_cod_code',
--                         'confirm_cod_delivery','order_record_sales');
--
-- 2. Earnings still reconcile for someone who has never ordered — the
--    two new sums must be 0 and the numbers unchanged:
--      select public.get_member_earnings(<member_id>);
--
-- 3. In the app, the two paths that were silent before:
--      • member confirms a Delivered order  -> one `sales` row per line,
--        stock decremented, orders.sales_recorded_at set.
--      • rider scans the member's CoD code  -> Completed, paid, same.
--    Then complete the same order again: nothing should change, because
--    sales_recorded_at is already set.
--
-- 4. Paying with funds must move the member's own earnings screen:
--      select public.get_member_earnings(<member_id>);   -- before
--      -- pay an Agreed order from Balance
--      select public.get_member_earnings(<member_id>);   -- balance down
--    and paying more than the bucket holds must be refused.

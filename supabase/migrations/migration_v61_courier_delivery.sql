-- ═══════════════════════════════════════════════════════════════════
-- Migration v61 — Courier delivery (LBC / J&T) and outside payment
--
-- Requires v60's chain for orders: v52 (sales recording, CoD code), v55
-- (can_handle_orders, complete_delivery_order), v56 (pay_order_with_funds),
-- v57 (refunds on cancel), v59 (cashier_assign_rider, the push trigger).
--
-- ── What the client asked for (2026-10-01) ─────────────────────────
-- While pricing, the cashier or admin chooses how the order travels:
-- our own rider, as before, or a courier, LBC or J&T. A courier order:
--   • cannot be paid cash on delivery;
--   • is paid from Balance or Total Earnings (as before), or OUTSIDE the
--     app (GCash or similar). For an outside payment the staff send the
--     payment details, the member pays and says so, and the staff confirm
--     the money arrived. No money moves inside the app for it;
--   • is booked with the courier by the staff, outside the app, then
--     marked Shipped here with its tracking number;
--   • completes when the member taps "I received it". That is when the
--     sale is recorded and Group Sales commissions are paid to the
--     buyer's upline, exactly as for rider orders (v19, via sales rows).
--
-- The open questions were settled with the suggested answers in the
-- "Courier Delivery Flow (LBC / J&T)" doc:
--   • admins and main cashiers both choose the route;
--   • payment details are typed into the order and shown in the app;
--   • rider orders do not get the outside payment;
--   • the route is part of the quote: set (or changed) with each quote;
--   • the courier's shipping fee is the delivery fee, negotiable as now;
--   • a tracking number is required to mark an order Shipped;
--   • STOCK leaves at Shipped, not at completion: a parcel can be in
--     transit for days, and the shelf count must not include it. The sale
--     and the commissions still wait for "I received it";
--   • staff can mark a Shipped order received (cashier_override) when
--     the member never taps;
--   • an outside payment that does not arrive is sent back with a note;
--     the member can pay again or switch to Balance / Total Earnings;
--   • a Shipped order is cancelled only by staff, saying whether the
--     parcel came back (stock returned) or was lost (it was not).
--     Balance / Total Earnings are refunded as on any cancel; an outside
--     payment is refunded outside the app.
--
-- ── Statuses ───────────────────────────────────────────────────────
-- Rider:   … Agreed → Assigned → Picked Up → Delivered → Completed
-- Courier: … Agreed → Shipped → Completed
-- Payment is not a status (as in v59): an Agreed courier order waits with
-- payment_status 'unpaid' until it is paid or the outside payment is
-- confirmed.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_courier_delivery_v61.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Columns and constraints ─────────────────────────────────────
alter table public.orders
  add column if not exists delivery_route        text not null default 'rider',
  add column if not exists payment_details       text,
  add column if not exists payment_details_at    timestamptz,
  add column if not exists payment_sent_at       timestamptz,
  add column if not exists payment_reference     text,
  add column if not exists payment_rejected_note text,
  add column if not exists payment_rejected_at   timestamptz,
  add column if not exists tracking_number       text,
  add column if not exists shipped_at            timestamptz,
  add column if not exists stock_taken_at        timestamptz;

alter table public.orders drop constraint if exists orders_delivery_route_check;
alter table public.orders add constraint orders_delivery_route_check
  check (delivery_route in ('rider', 'lbc', 'jnt'));

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check
  check (status in (
    'Order Placed',
    'Cashier Pricing & Negotiating',
    'Member Negotiating',
    'Agreed',
    'Assigned',
    'Picked Up',
    'Delivered',
    'Shipped',
    'Completed',
    'Cancelled'
  ));

alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (payment_method is null
         or payment_method in ('funds', 'cod', 'counter', 'outside'));

-- ── 2. Stock, separated from the sale ──────────────────────────────
-- Internal helpers: the callers below have authorized themselves.

-- Takes an order's goods off the shelf. Idempotent through
-- stock_taken_at, so a courier order (taken at Shipped) is not taken
-- again when its sale is recorded. Same arithmetic as v52.
create or replace function public._order_take_stock(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_taken  timestamptz;
  v_line   record;
  v_stock  int;
  v_thresh int;
begin
  select stock_taken_at into v_taken
    from public.orders where id = p_order_id for update;
  if v_taken is not null then
    return;
  end if;

  for v_line in
    select product_id, quantity
      from public.order_items
     where order_id = p_order_id
     order by id
  loop
    select i.stock,
           coalesce(
             c.low_stock_threshold,
             (select value::int from public.app_config
               where key = 'low_stock_threshold'),
             50
           )
      into v_stock, v_thresh
      from public.items i
      left join public.categories c on c.name = i.category
     where i.id = v_line.product_id
       for update of i;

    -- A product deleted since the order was placed has no shelf to
    -- take from; its sale is still recorded later.
    if found then
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
  end loop;

  update public.orders set stock_taken_at = now() where id = p_order_id;
end;
$$;

-- Puts a returned parcel's goods back. Only for an order whose sale was
-- never recorded (a cancelled Shipped order).
create or replace function public._order_return_stock(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_taken  timestamptz;
  v_sold   timestamptz;
  v_line   record;
  v_stock  int;
  v_thresh int;
begin
  select stock_taken_at, sales_recorded_at into v_taken, v_sold
    from public.orders where id = p_order_id for update;
  if v_taken is null or v_sold is not null then
    return;
  end if;

  for v_line in
    select product_id, quantity
      from public.order_items
     where order_id = p_order_id
     order by id
  loop
    select i.stock,
           coalesce(
             c.low_stock_threshold,
             (select value::int from public.app_config
               where key = 'low_stock_threshold'),
             50
           )
      into v_stock, v_thresh
      from public.items i
      left join public.categories c on c.name = i.category
     where i.id = v_line.product_id
       for update of i;

    if found then
      v_stock := v_stock + v_line.quantity;
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
  end loop;

  update public.orders set stock_taken_at = null where id = p_order_id;
end;
$$;

-- v52's function. Changed: the stock half moved into _order_take_stock,
-- which does nothing when the stock already left at Shipped. The sales
-- rows, and so the commissions, are written exactly as before.
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
  v_buyer   text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;

  -- Idempotent. Several completion paths reach this, and a retry after a
  -- dropped connection must not sell the same goods twice.
  if v_order.sales_recorded_at is not null then
    return;
  end if;

  perform public._order_take_stock(p_order_id);

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
    select i.name into v_name from public.items i where i.id = v_line.product_id;

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

-- ── 3. Refunds, shared by both cancels ─────────────────────────────
-- v57's refund block, unchanged, as a helper. Returns true when a funds
-- payment was given back. An outside payment is not touched: its money
-- never entered the app, so it is refunded outside it.
create or replace function public._order_refund_funds(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_member bigint;
  v_method text;
  v_paid   text;
  v_txn    bigint;
  v_amount integer;
  v_label  text;
  v_prefix text;
begin
  select member_id, payment_method, payment_status, payment_transaction_id
    into v_member, v_method, v_paid, v_txn
    from public.orders where id = p_order_id for update;

  if v_method is distinct from 'funds' or v_paid is distinct from 'paid' then
    return false;
  end if;

  select price, item_name into v_amount, v_label
    from public.member_transactions where id = v_txn;
  if v_amount is null then
    -- Refusing is the only safe answer: cancelling without it would
    -- keep the member's money with no record of what it was for.
    raise exception 'Cannot cancel: the payment for this order was not found, so it cannot be refunded. Ask an admin.';
  end if;
  v_prefix := case when v_label ilike 'Order Payment (Balance)%'
                   then 'Order Payment (Balance)'
                   else 'Order Payment (Earnings)' end;

  perform public._lock_member_funds(v_member);
  insert into public.member_transactions
    (user_id, member_id, sale_id, item_id, item_name, quantity, price, timestamp)
  values
    (auth.uid(), v_member, null, null,
     v_prefix || ' — Refund, Order #' || left(p_order_id::text, 8),
     1, -v_amount, now());
  return true;
end;
$$;

-- ── 4. Cancel (v57), with Shipped handled separately ───────────────
create or replace function public.cancel_delivery_order(
  p_order_id uuid,
  p_reason   text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status   text;
  v_member   bigint;
  v_owner    uuid;
  v_rider    uuid;
  v_refunded boolean;
begin
  select status, member_id, cashier_id, delivery_id
    into v_status, v_member, v_owner, v_rider
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_status in ('Completed', 'Cancelled') then
    raise exception 'Order is already %', lower(v_status);
  end if;
  -- NEW (v61): a parcel with the courier needs to say whether it came
  -- back, which this function cannot ask.
  if v_status = 'Shipped' then
    if v_member = public.my_member_id() and not public.is_admin() then
      raise exception 'The order is already with the courier — contact the store';
    end if;
    raise exception 'This order was already shipped: use "Cancel shipped order" and say whether the parcel came back';
  end if;

  if public.is_admin() then
    null;
  elsif v_member = public.my_member_id() then
    -- A member may back out until the goods are moving.
    if v_status in ('Picked Up', 'Delivered') then
      raise exception 'The order is already on its way — contact the cashier';
    end if;
  elsif public.can_handle_orders() and (v_owner = auth.uid() or v_owner is null) then
    null;
  elsif public.is_delivery() and v_rider = auth.uid() then
    if coalesce(btrim(p_reason), '') = '' then
      raise exception 'A reason is required when a rider cancels';
    end if;
  else
    raise exception 'Not authorized to cancel this order';
  end if;

  v_refunded := public._order_refund_funds(p_order_id);

  update public.orders
     set status         = 'Cancelled',
         cancel_reason  = nullif(btrim(p_reason), ''),
         payment_status = case when v_refunded then 'refunded' else payment_status end
   where id = p_order_id;
end;
$$;

-- A Shipped order the courier could not deliver, or lost.
-- p_returned: the parcel came back, so its goods go back on the shelf.
create or replace function public.cashier_cancel_shipped_order(
  p_order_id uuid,
  p_reason   text,
  p_returned boolean
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status   text;
  v_owner    uuid;
  v_refunded boolean;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select status, cashier_id into v_status, v_owner
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;
  if v_status <> 'Shipped' then
    raise exception 'Only a shipped order is cancelled this way (status "%")', v_status;
  end if;
  if coalesce(btrim(p_reason), '') = '' then
    raise exception 'Say what happened to the parcel';
  end if;
  if p_returned is null then
    raise exception 'Say whether the parcel came back';
  end if;

  v_refunded := public._order_refund_funds(p_order_id);
  if p_returned then
    perform public._order_return_stock(p_order_id);
  end if;

  update public.orders
     set status         = 'Cancelled',
         cancel_reason  = btrim(p_reason)
                          || case when p_returned then ' (parcel returned)'
                                  else ' (parcel not returned)' end,
         payment_status = case when v_refunded then 'refunded' else payment_status end
   where id = p_order_id;
end;
$$;

-- ── 5. Quote, now with the route (v55 + p_route) ───────────────────
-- A new signature, so the old one goes. p_route defaults to 'rider', so
-- an app built before v61 (which sends five arguments) still quotes.
drop function if exists public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb);

create or replace function public.cashier_send_quote(
  p_order_id     uuid,
  p_cashier_id   uuid,
  p_items_total  numeric,
  p_delivery_fee numeric,
  p_lines        jsonb,
  p_route        text default 'rider'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line   jsonb;
  v_status text;
  v_owner  uuid;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  if p_cashier_id <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: a quote is sent under your own account';
  end if;
  if not exists (
    select 1 from public.profiles
     where id = p_cashier_id and role in ('admin', 'cashier')
  ) then
    raise exception 'An order can only be handled by an admin or cashier';
  end if;
  if coalesce(p_route, 'rider') not in ('rider', 'lbc', 'jnt') then
    raise exception 'Unknown delivery route "%"', p_route;
  end if;

  select status, cashier_id into v_status, v_owner
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_status not in ('Order Placed', 'Member Negotiating') then
    raise exception 'Cannot quote an order in status "%"', v_status;
  end if;
  if v_owner is not null and v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Another cashier is already handling this order';
  end if;

  update public.orders
     set cashier_id     = p_cashier_id,
         items_total    = p_items_total,
         delivery_fee   = p_delivery_fee,
         delivery_route = coalesce(p_route, 'rider'),
         status         = 'Cashier Pricing & Negotiating'
   where id = p_order_id;

  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    update public.order_items
       set unit_price = (v_line->>'unit_price')::numeric,
           subtotal   = (v_line->>'subtotal')::numeric
     where order_id = p_order_id
       and product_id = (v_line->>'product_id')::bigint;
  end loop;
end;
$$;

-- ── 6. No cash on delivery for a courier (v52 + one check) ─────────
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
  -- NEW (v61)
  if v_order.delivery_route <> 'rider' then
    raise exception 'Cash on delivery is not available for orders sent by LBC or J&T';
  end if;
  if v_order.status not in ('Agreed', 'Assigned', 'Picked Up') then
    raise exception 'No code to show for an order in status "%"', v_order.status;
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;

  if v_order.cod_nonce is null then
    update public.orders
       set cod_nonce      = replace(gen_random_uuid()::text, '-', ''),
           payment_method = 'cod'
     where id = p_order_id
    returning cod_nonce into v_order.cod_nonce;
  end if;

  return v_order.cod_nonce;
end;
$$;

-- ── 7. Outside payment ─────────────────────────────────────────────
-- Shared checks for the staff side: who, which order, which state.
create or replace function public._assert_outside_payment_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.cashier_id <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;
  if v_order.status <> 'Agreed' then
    raise exception 'Payment is settled while the order is Agreed (status "%")', v_order.status;
  end if;
  if v_order.payment_method is distinct from 'outside' then
    raise exception 'The member has not chosen to pay outside the app';
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;
end;
$$;

-- The member chooses GCash or another payment outside the app.
create or replace function public.member_choose_outside_payment(p_order_id uuid)
returns void
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
  if v_order.delivery_route = 'rider' then
    raise exception 'Paying outside the app is only for orders sent by LBC or J&T';
  end if;
  if v_order.status <> 'Agreed' then
    raise exception 'An order can only be paid once both sides have agreed (status "%")', v_order.status;
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;

  update public.orders
     set payment_method = 'outside'
   where id = p_order_id;
end;
$$;

-- Staff tell the member where to pay: number, account name, amount.
create or replace function public.cashier_send_payment_details(
  p_order_id uuid,
  p_details  text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._assert_outside_payment_order(p_order_id);
  if coalesce(btrim(p_details), '') = '' then
    raise exception 'Write where the member should send the payment';
  end if;

  update public.orders
     set payment_details    = btrim(p_details),
         payment_details_at = now()
   where id = p_order_id;
end;
$$;

-- The member says they sent it, optionally with the reference number.
create or replace function public.member_mark_payment_sent(
  p_order_id  uuid,
  p_reference text default null
) returns void
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
  if v_order.status <> 'Agreed'
     or v_order.payment_method is distinct from 'outside'
     or v_order.payment_status = 'paid' then
    raise exception 'There is no outside payment waiting on this order';
  end if;
  if v_order.payment_details_at is null then
    raise exception 'Wait for the store to send where to pay';
  end if;

  update public.orders
     set payment_sent_at       = now(),
         payment_reference     = nullif(btrim(p_reference), ''),
         payment_rejected_note = null,
         payment_rejected_at   = null
   where id = p_order_id;
end;
$$;

-- Staff checked: the money arrived.
create or replace function public.cashier_confirm_outside_payment(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._assert_outside_payment_order(p_order_id);

  update public.orders
     set payment_status        = 'paid',
         paid_at               = now(),
         payment_rejected_note = null,
         payment_rejected_at   = null
   where id = p_order_id;
end;
$$;

-- Staff checked: it did not arrive, or does not match. The member is told
-- why and can send it again, or pay from their funds instead.
create or replace function public.cashier_reject_outside_payment(
  p_order_id uuid,
  p_note     text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._assert_outside_payment_order(p_order_id);
  if coalesce(btrim(p_note), '') = '' then
    raise exception 'Tell the member what was wrong with the payment';
  end if;

  update public.orders
     set payment_sent_at       = null,
         payment_rejected_note = btrim(p_note),
         payment_rejected_at   = now()
   where id = p_order_id;
end;
$$;

-- ── 8. Shipped ─────────────────────────────────────────────────────
-- Booked with the courier. The goods leave the shelf now.
create or replace function public.cashier_mark_shipped(
  p_order_id uuid,
  p_tracking text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.cashier_id <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;
  if v_order.delivery_route = 'rider' then
    raise exception 'This order goes by rider, not by courier';
  end if;
  if v_order.status <> 'Agreed' then
    raise exception 'Only an agreed order can be shipped (status "%")', v_order.status;
  end if;
  if v_order.payment_status is distinct from 'paid' then
    raise exception 'Waiting for the member to pay: confirm the payment before shipping';
  end if;
  if coalesce(btrim(p_tracking), '') = '' then
    raise exception 'Enter the tracking number from the courier';
  end if;

  update public.orders
     set status          = 'Shipped',
         shipped_at      = now(),
         tracking_number = btrim(p_tracking)
   where id = p_order_id;

  perform public._order_take_stock(p_order_id);
end;
$$;

-- ── 9. Received ────────────────────────────────────────────────────
-- v52's function; a Shipped order can now be confirmed too.
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
  if v_status not in ('Delivered', 'Shipped') then
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

-- v55's function; staff can close a Shipped order the member never
-- confirmed, once the courier shows it delivered.
create or replace function public.complete_delivery_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_owner  uuid;
  v_paid   text;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select status, cashier_id, payment_status into v_status, v_owner, v_paid
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;

  if v_status = 'Agreed' then
    update public.orders
       set status         = 'Completed',
           -- Already paid: that payment stands. Otherwise the member is
           -- paying the cashier in person, right now.
           payment_method = case when v_paid = 'paid' then payment_method else 'counter' end,
           payment_status = 'paid',
           paid_at        = coalesce(paid_at, now())
     where id = p_order_id;
  elsif v_status in ('Delivered', 'Shipped') then
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

-- ── 10. No rider for a courier order (v59 + one check) ─────────────
create or replace function public.cashier_assign_rider(
  p_order_id uuid,
  p_rider_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status  text;
  v_owner   uuid;
  v_role    text;
  v_paid    text;
  v_method  text;
  v_route   text;
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select status, cashier_id, payment_status, payment_method, delivery_route
    into v_status, v_owner, v_paid, v_method, v_route
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;
  -- NEW (v61)
  if v_route <> 'rider' then
    raise exception 'This order goes by LBC or J&T, not by rider';
  end if;
  if v_status not in ('Agreed', 'Assigned') then
    raise exception 'A rider can only be assigned to an agreed order (status "%")', v_status;
  end if;
  if v_status = 'Agreed'
     and v_paid is distinct from 'paid'
     and v_method is distinct from 'cod' then
    raise exception 'Waiting for the member to pay: they must pay from their funds or choose cash on delivery before a rider is assigned';
  end if;

  select role into v_role from public.profiles where id = p_rider_id;
  if v_role is distinct from 'delivery' then
    raise exception 'That account is not a delivery rider';
  end if;

  update public.orders
     set delivery_id = p_rider_id,
         assigned_at = now(),
         status      = 'Assigned'
   where id = p_order_id;
end;
$$;

-- ── 11. Push: the outside-payment steps change no status ───────────
-- v59's trigger function plus `event`, which names the payment step that
-- just happened (or null), so order-push can tell the right person.
create or replace function public.queue_order_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
  v_event  text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'order_push_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'order_push_secret';
  if v_url is null or v_secret is null then
    return new;   -- not configured in this environment
  end if;

  if tg_op = 'UPDATE' then
    v_event := case
      when new.payment_details_at is distinct from old.payment_details_at
           and new.payment_details_at is not null then 'payment_details'
      when new.payment_sent_at is distinct from old.payment_sent_at
           and new.payment_sent_at is not null then 'payment_sent'
      when new.payment_rejected_at is distinct from old.payment_rejected_at
           and new.payment_rejected_at is not null then 'payment_rejected'
    end;
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_secret),
    body    := jsonb_build_object(
                 'order_id',           new.id,
                 'type',               lower(tg_op),
                 'old_status',         case when tg_op = 'UPDATE' then old.status end,
                 'old_delivery_id',    case when tg_op = 'UPDATE' then old.delivery_id end,
                 'old_payment_status', case when tg_op = 'UPDATE' then old.payment_status end,
                 'old_payment_method', case when tg_op = 'UPDATE' then old.payment_method end,
                 'event',              v_event,
                 -- Whoever made the change is not told about it.
                 'actor',              auth.uid())
  );
  return new;
exception when others then
  -- A notification is never worth failing an order update for.
  raise warning 'order push not queued for %: %', new.id, sqlerrm;
  return new;
end;
$$;

drop trigger if exists orders_push_update on public.orders;
create trigger orders_push_update
  after update of status, delivery_id, payment_status, payment_method,
                  payment_details_at, payment_sent_at, payment_rejected_at
  on public.orders
  for each row
  when (old.status is distinct from new.status
        or old.delivery_id is distinct from new.delivery_id
        or old.payment_status is distinct from new.payment_status
        or old.payment_method is distinct from new.payment_method
        or old.payment_details_at is distinct from new.payment_details_at
        or old.payment_sent_at is distinct from new.payment_sent_at
        or old.payment_rejected_at is distinct from new.payment_rejected_at)
  execute function public.queue_order_push();

-- ── 12. Grants ─────────────────────────────────────────────────────
-- create or replace keeps the grants on the redefined RPCs. New ones:
revoke all on function public._order_take_stock(uuid) from public;
revoke all on function public._order_return_stock(uuid) from public;
revoke all on function public._order_refund_funds(uuid) from public;
revoke all on function public._assert_outside_payment_order(uuid) from public;
revoke all on function public.queue_order_push() from public;

revoke all on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb, text) from public;
grant execute on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb, text) to authenticated;

revoke all on function public.cashier_cancel_shipped_order(uuid, text, boolean) from public;
grant execute on function public.cashier_cancel_shipped_order(uuid, text, boolean) to authenticated;

revoke all on function public.member_choose_outside_payment(uuid) from public;
grant execute on function public.member_choose_outside_payment(uuid) to authenticated;

revoke all on function public.cashier_send_payment_details(uuid, text) from public;
grant execute on function public.cashier_send_payment_details(uuid, text) to authenticated;

revoke all on function public.member_mark_payment_sent(uuid, text) from public;
grant execute on function public.member_mark_payment_sent(uuid, text) to authenticated;

revoke all on function public.cashier_confirm_outside_payment(uuid) from public;
grant execute on function public.cashier_confirm_outside_payment(uuid) to authenticated;

revoke all on function public.cashier_reject_outside_payment(uuid, text) from public;
grant execute on function public.cashier_reject_outside_payment(uuid, text) to authenticated;

revoke all on function public.cashier_mark_shipped(uuid, text) from public;
grant execute on function public.cashier_mark_shipped(uuid, text) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (61, 'courier_delivery')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. One cashier_send_quote, with six arguments:
--      select pg_get_function_identity_arguments(oid)
--        from pg_proc where proname = 'cashier_send_quote';
-- 2. Every existing order is a rider order:
--      select delivery_route, count(*) from public.orders group by 1;
-- 3. In the app (staging), as cashier and member:
--      • price an order with LBC: the member's payment choices have no
--        cash on delivery;
--      • member picks GCash / other: the cashier sends details, the member
--        taps "I've sent it", the cashier confirms;
--      • cashier marks it Shipped with a tracking number: the product's
--        stock drops now; the member's upline Group Sales does not move;
--      • member taps "I received it": Group Sales goes up, stock does not
--        drop a second time.
-- 4. Deploy order-push from the same commit, or the payment-step alerts
--    reach an older function that ignores them (harmless, silent).

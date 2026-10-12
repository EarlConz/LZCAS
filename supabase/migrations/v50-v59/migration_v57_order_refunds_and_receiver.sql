-- ═══════════════════════════════════════════════════════════════════
-- Migration v57 — Cancelled orders refund their funds, and checkout
--                 names who receives the order
--
-- Requires v56 (_lock_member_funds) and v55 (the latest
-- cancel_delivery_order).
--
-- ── 1. A paid order that is cancelled gives the money back ─────────
-- pay_order_with_funds (v52) takes payment at Agreed, and an order can
-- still be cancelled after that: by the member until the rider picks it
-- up, by the cashier or an admin, or by the rider when the member refuses
-- it (the client's rule: the rider brings the goods back). Until now the
-- cancel kept the payment. The member's funds went down and stayed down
-- for an order they never received.
--
-- cancel_delivery_order now reverses a funds payment in the same step:
-- one POSITIVE member_transactions row, the exact amount of the payment
-- row, under the same 'Order Payment (Balance|Earnings)' prefix. Every sum
-- that subtracted the payment — get_member_earnings, the v56 withdrawal
-- check, the overdraft audit — adds the refund back with no change of its
-- own, and the payment and its refund both stay on the ledger. The order
-- is marked payment_status = 'refunded'.
--
-- Only funds payments are refunded. Cash is taken only at handover, which
-- completes the order, and a completed order cannot be cancelled. A
-- counter sale is the same.
--
-- Stock needs nothing: order_record_sales (v52) writes the sale and
-- takes the stock only at completion, so a cancelled order never took any.
--
-- ── 2. Receiver at checkout ────────────────────────────────────────
-- orders.receiver_name / receiver_contact exist since v50 and the rider's
-- screens show them, but create_delivery_order had no way to fill them.
-- It gains two optional parameters. Left out (or blank), the rider sees
-- the member's own name, exactly as now.
--
-- The old five-argument function is DROPPED, not overloaded: adding a
-- second version with defaulted extras would make every five-argument
-- call ambiguous between the two. Named calls from the current app still
-- match the new one, because the extras default to null.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_order_refunds_and_receiver_v57.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. 'refunded' is a payment state ───────────────────────────────
alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
  check (payment_status in ('unpaid', 'paid', 'refunded'));

-- ── 2. Cancel, with the refund ─────────────────────────────────────
-- v55's body. Changed: the refund block before the final update, and the
-- payment_status it sets.
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
  v_method   text;
  v_paid     text;
  v_txn      bigint;
  v_amount   integer;
  v_label    text;
  v_prefix   text;
  v_refunded boolean := false;
begin
  select status, member_id, cashier_id, delivery_id,
         payment_method, payment_status, payment_transaction_id
    into v_status, v_member, v_owner, v_rider, v_method, v_paid, v_txn
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_status in ('Completed', 'Cancelled') then
    raise exception 'Order is already %', lower(v_status);
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

  -- NEW (v57): give a funds payment back.
  if v_method = 'funds' and v_paid = 'paid' then
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
    v_refunded := true;
  end if;

  update public.orders
     set status         = 'Cancelled',
         cancel_reason  = nullif(btrim(p_reason), ''),
         payment_status = case when v_refunded then 'refunded' else payment_status end
   where id = p_order_id;
end;
$$;

-- ── 3. Checkout names the receiver ─────────────────────────────────
drop function if exists public.create_delivery_order(
  bigint, text, double precision, double precision, jsonb
);

-- v49's body, plus the two receiver parameters.
create or replace function public.create_delivery_order(
  p_member_id          bigint,
  p_delivery_address   text,
  p_delivery_latitude  double precision,
  p_delivery_longitude double precision,
  p_items              jsonb,
  p_receiver_name      text default null,
  p_receiver_contact   text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id   uuid;
  v_line       jsonb;
  v_product_id bigint;
  v_quantity   integer;
begin
  if not (public.is_admin() or p_member_id = public.my_member_id()) then
    raise exception 'Not authorized: you may only place an order for yourself';
  end if;
  if p_items is null or jsonb_array_length(p_items) = 0 then
    raise exception 'An order needs at least one item';
  end if;

  insert into public.orders (
    member_id, delivery_address, delivery_latitude, delivery_longitude,
    receiver_name, receiver_contact, status
  ) values (
    p_member_id, p_delivery_address, p_delivery_latitude, p_delivery_longitude,
    nullif(btrim(p_receiver_name), ''), nullif(btrim(p_receiver_contact), ''),
    'Order Placed'
  )
  returning id into v_order_id;

  for v_line in select * from jsonb_array_elements(p_items)
  loop
    v_product_id := (v_line->>'product_id')::bigint;
    v_quantity   := coalesce((v_line->>'quantity')::integer, 1);
    if v_quantity > 0 then
      insert into public.order_items (order_id, product_id, quantity)
      values (v_order_id, v_product_id, v_quantity);
    end if;
  end loop;

  return v_order_id;
end;
$$;

-- ── 4. Grants ──────────────────────────────────────────────────────
-- The new create_delivery_order is a new function: it needs its grant.
-- cancel_delivery_order keeps its own through create or replace.
revoke all on function public.create_delivery_order(
  bigint, text, double precision, double precision, jsonb, text, text
) from public;
grant execute on function public.create_delivery_order(
  bigint, text, double precision, double precision, jsonb, text, text
) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (57, 'order_refunds_and_receiver')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. One create_delivery_order, with seven arguments:
--      select pg_get_function_identity_arguments(oid)
--        from pg_proc where proname = 'create_delivery_order';
-- 2. Paid orders that were cancelled BEFORE v57 kept the member's money.
--    This lists them; each needs a refund by hand (an admin adjustment,
--    or ask me for a one-off script):
--      select o.id, o.member_id, o.final_total, o.updated_at
--        from public.orders o
--       where o.status = 'Cancelled'
--         and o.payment_method = 'funds'
--         and o.payment_status = 'paid';
-- 3. In the app, as a member with Balance:
--      • pay an Agreed order from Balance: Balance goes down.
--      • cancel it: Balance comes back to the same figure, the order reads
--        "Refunded", and the earnings list shows both the purchase and the
--        refund.
--      • check out with a different receiver: the rider's screen shows
--        that name and number.

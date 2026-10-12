-- ═══════════════════════════════════════════════════════════════════
-- Rollback v61 — Courier delivery (LBC / J&T) and outside payment
--
-- Restores every function v61 redefined, copied verbatim from the
-- migration named above each one, drops the functions v61 added, and
-- drops its columns.
--
-- Read first:
--   • Refuses to run while any order is a courier order, is Shipped, or
--     was paid outside the app: those rows would break the restored
--     constraints and lose their payment record. Finish or cancel them
--     first (the check below lists what is blocking).
--   • Roll the app back too: a v61 build sends the route with every quote
--     and offers the courier steps, which the restored database refuses.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  v_blocking int;
begin
  select count(*) into v_blocking
    from public.orders
   where delivery_route <> 'rider'
      or status = 'Shipped'
      or payment_method = 'outside';
  if v_blocking > 0 then
    raise exception 'Rollback v61 refused: % order(s) use the courier route, are Shipped, or were paid outside the app. List them with: select id, status, delivery_route, payment_method from public.orders where delivery_route <> ''rider'' or status = ''Shipped'' or payment_method = ''outside'';', v_blocking;
  end if;
end $$;

-- ── Functions v61 added ────────────────────────────────────────────
drop function if exists public.cashier_cancel_shipped_order(uuid, text, boolean);
drop function if exists public.member_choose_outside_payment(uuid);
drop function if exists public.cashier_send_payment_details(uuid, text);
drop function if exists public.member_mark_payment_sent(uuid, text);
drop function if exists public.cashier_confirm_outside_payment(uuid);
drop function if exists public.cashier_reject_outside_payment(uuid, text);
drop function if exists public.cashier_mark_shipped(uuid, text);
drop function if exists public._assert_outside_payment_order(uuid);

-- ── Restored bodies ────────────────────────────────────────────────
-- v52
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

-- v52
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

-- v52
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

-- v55
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
           -- Already paid from funds: that payment stands. Otherwise the
           -- member is paying the cashier in person, right now.
           payment_method = case when v_paid = 'paid' then payment_method else 'counter' end,
           payment_status = 'paid',
           paid_at        = coalesce(paid_at, now())
     where id = p_order_id;
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

-- v57
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

-- v59
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
begin
  if not public.can_handle_orders() then
    raise exception 'Not authorized: only admins and cashiers handle delivery orders';
  end if;
  select status, cashier_id, payment_status, payment_method
    into v_status, v_owner, v_paid, v_method
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_owner <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: another cashier is handling this order';
  end if;
  -- Re-assignment from Assigned is allowed (rider unavailable); from
  -- Picked Up it is not — the goods are already moving.
  if v_status not in ('Agreed', 'Assigned') then
    raise exception 'A rider can only be assigned to an agreed order (status "%")', v_status;
  end if;
  -- NEW (v59): first dispatch waits for payment or a cash choice.
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

-- v55: the five-argument quote
drop function if exists public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb, text);
create or replace function public.cashier_send_quote(
  p_order_id     uuid,
  p_cashier_id   uuid,
  p_items_total  numeric,
  p_delivery_fee numeric,
  p_lines        jsonb
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
     set cashier_id   = p_cashier_id,
         items_total  = p_items_total,
         delivery_fee = p_delivery_fee,
         status       = 'Cashier Pricing & Negotiating'
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
revoke all on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb) from public;
grant execute on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb) to authenticated;

-- v59: the push trigger without the payment-step event
create or replace function public.queue_order_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'order_push_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'order_push_secret';
  if v_url is null or v_secret is null then
    return new;   -- not configured in this environment
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
  after update of status, delivery_id, payment_status, payment_method on public.orders
  for each row
  when (old.status is distinct from new.status
        or old.delivery_id is distinct from new.delivery_id
        or old.payment_status is distinct from new.payment_status
        or old.payment_method is distinct from new.payment_method)
  execute function public.queue_order_push();

-- Helpers the restored bodies no longer call.
drop function if exists public._order_refund_funds(uuid);
drop function if exists public._order_take_stock(uuid);
drop function if exists public._order_return_stock(uuid);

-- ── Constraints and columns ────────────────────────────────────────
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (payment_method is null or payment_method in ('funds', 'cod', 'counter'));

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
    'Completed',
    'Cancelled'
  ));

alter table public.orders drop constraint if exists orders_delivery_route_check;
alter table public.orders
  drop column if exists delivery_route,
  drop column if exists payment_details,
  drop column if exists payment_details_at,
  drop column if exists payment_sent_at,
  drop column if exists payment_reference,
  drop column if exists payment_rejected_note,
  drop column if exists payment_rejected_at,
  drop column if exists tracking_number,
  drop column if exists shipped_at,
  drop column if exists stock_taken_at;

delete from public.schema_migrations where version = 61;

notify pgrst, 'reload schema';

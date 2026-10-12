-- ═══════════════════════════════════════════════════════════════════
-- Rollback v57 — Refunds on cancel, receiver at checkout
--
-- Restores v55's cancel_delivery_order and v49's five-argument
-- create_delivery_order (both copied verbatim below).
--
-- Read first:
--   • Refunds already made stay made. Their ledger rows are real money
--     returned to members and are not touched.
--   • Cancelling a paid order stops refunding again.
--   • The app built with v57 always sends the receiver to
--     create_delivery_order. After this rollback that call fails ("function
--     not found"), so checkout breaks until the app is rolled back too, or
--     v57 is re-applied.
--   • 'refunded' stays an allowed payment_status if any order holds it;
--     otherwise the constraint goes back to unpaid / paid.
-- ═══════════════════════════════════════════════════════════════════

-- v55
create or replace function public.cancel_delivery_order(
  p_order_id uuid,
  p_reason   text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_member bigint;
  v_owner  uuid;
  v_rider  uuid;
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

  update public.orders
     set status        = 'Cancelled',
         cancel_reason = nullif(btrim(p_reason), '')
   where id = p_order_id;
end;
$$;

drop function if exists public.create_delivery_order(
  bigint, text, double precision, double precision, jsonb, text, text
);

-- v49
create or replace function public.create_delivery_order(
  p_member_id          bigint,
  p_delivery_address   text,
  p_delivery_latitude  double precision,
  p_delivery_longitude double precision,
  p_items              jsonb
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
    member_id, delivery_address, delivery_latitude, delivery_longitude, status
  ) values (
    p_member_id, p_delivery_address, p_delivery_latitude, p_delivery_longitude,
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

revoke all on function public.create_delivery_order(bigint, text, double precision, double precision, jsonb) from public;
grant execute on function public.create_delivery_order(bigint, text, double precision, double precision, jsonb) to authenticated;

do $$
begin
  if not exists (select 1 from public.orders where payment_status = 'refunded') then
    alter table public.orders drop constraint if exists orders_payment_status_check;
    alter table public.orders add constraint orders_payment_status_check
      check (payment_status in ('unpaid', 'paid'));
  else
    raise notice 'v57 rollback: refunded orders exist; payment_status still accepts ''refunded''.';
  end if;
end $$;

delete from public.schema_migrations where version = 57;

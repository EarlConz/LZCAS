-- ═══════════════════════════════════════════════════════════════════
-- Migration v50 — The delivery rider
--
-- A new profiles.role = 'delivery'. Takes an agreed order from the
-- cashier, carries it to the member, hands it over. See
-- docs/delivery_system_plan.md §1 for the reasoning behind every
-- choice here; this header covers only what the SQL does.
--
-- Requires v49 (the caller checks and is_delivery()).
--
-- ── The state machine, extended ────────────────────────────────────
--
--   Agreed → Assigned → Picked Up → Delivered → Completed
--               └──────────┴────────────┴──────→ Cancelled
--
--   Assigned   cashier picked a rider          cashier_assign_rider
--   Picked Up  rider has the goods, ETA set    delivery_pickup
--   Delivered  rider says it is handed over    delivery_mark_delivered
--   Completed  the member confirms receipt     member_confirm_received
--              — or the cashier closes it     complete_delivery_order
--
-- Delivered and Completed are two states on purpose: the rider's claim
-- and the member's confirmation are different facts, and a dispute
-- lives between them. There is no auto-complete on a timer.
--
-- The rider is OPTIONAL per order. complete_delivery_order still
-- accepts an Agreed order with no rider — the cashier hands it over at
-- the counter, as v48 intended — so nothing about the existing flow
-- breaks for orders that never get a rider.
--
-- ── Payment columns, no payment RPCs ───────────────────────────────
-- payment_method / payment_status land here so the rider's screens can
-- show them, but NOTHING sets them yet. v51 adds the two RPCs that do
-- (pay_order_with_funds, confirm_cod_delivery). Until then they are
-- null and the app shows "not set".
--
-- ── profiles.role has no CHECK ─────────────────────────────────────
-- 'delivery' is a convention, not a constraint, same as every other
-- role. The app's UserRole.fromString THROWS on an unknown value, so
-- the build that knows this role must ship BEFORE the first rider
-- account exists — the v28 rule.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_delivery_role_v50.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Columns ─────────────────────────────────────────────────────
alter table public.orders
  add column if not exists delivery_id         uuid,
  add column if not exists assigned_at         timestamptz,
  add column if not exists picked_up_at        timestamptz,
  add column if not exists eta_at              timestamptz,
  add column if not exists delivered_at        timestamptz,
  add column if not exists receiver_name       text,
  add column if not exists receiver_contact    text,
  add column if not exists confirmed_by        uuid,
  add column if not exists confirmed_at        timestamptz,
  add column if not exists confirmation_method text,
  add column if not exists cancel_reason       text,
  add column if not exists payment_method      text,
  add column if not exists payment_status      text not null default 'unpaid';

alter table public.orders drop constraint if exists orders_confirmation_method_check;
alter table public.orders add constraint orders_confirmation_method_check
  check (confirmation_method is null
         or confirmation_method in ('member_tap', 'qr', 'cashier_override'));

alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (payment_method is null or payment_method in ('funds', 'cod'));

alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check
  check (payment_status in ('unpaid', 'paid'));

-- Widen the status set. The v48 constraint is unnamed in some builds
-- and named orders_status_check in others, so drop by lookup.
do $$
declare
  c record;
begin
  for c in
    select conname from pg_constraint
    where conrelid = 'public.orders'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%status%in%'
      and pg_get_constraintdef(oid) not ilike '%payment_status%'
  loop
    execute format('alter table public.orders drop constraint %I', c.conname);
  end loop;
end $$;

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

create index if not exists idx_orders_delivery_id
  on public.orders (delivery_id, status);

-- ── 2. The rider arm of the read policy becomes real ───────────────
create or replace function public.order_rider_is_me(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.orders
    where id = p_order_id and delivery_id = auth.uid()
  );
$$;

-- ── 3. Dispatch ────────────────────────────────────────────────────
-- The cashier who quoted the order picks a rider. Riders do not
-- self-claim (plan §1: not enough riders to justify the race yet).
create or replace function public.cashier_assign_rider(
  p_order_id uuid,
  p_rider_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_owner  uuid;
  v_role   text;
begin
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to assign a rider';
  end if;
  select status, cashier_id into v_status, v_owner
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

-- ── 4. The rider's three moves ─────────────────────────────────────

-- Shared guard: caller is a rider, and THE rider on this order.
create or replace function public._assert_my_delivery(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_rider  uuid;
begin
  if not public.is_delivery() then
    raise exception 'Not authorized: delivery role required';
  end if;
  select status, delivery_id into v_status, v_rider
    from public.orders where id = p_order_id for update;
  if v_status is null then
    raise exception 'Order not found';
  end if;
  if v_rider is distinct from auth.uid() then
    raise exception 'Not authorized: this order is not assigned to you';
  end if;
  return v_status;
end;
$$;
revoke all on function public._assert_my_delivery(uuid) from public;

create or replace function public.delivery_pickup(
  p_order_id uuid,
  p_eta_at   timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  v_status := public._assert_my_delivery(p_order_id);
  if v_status <> 'Assigned' then
    raise exception 'Cannot pick up an order in status "%"', v_status;
  end if;
  if p_eta_at is null or p_eta_at <= now() then
    raise exception 'The ETA must be in the future';
  end if;
  update public.orders
     set status       = 'Picked Up',
         picked_up_at = now(),
         eta_at       = p_eta_at
   where id = p_order_id;
end;
$$;

create or replace function public.delivery_update_eta(
  p_order_id uuid,
  p_eta_at   timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  v_status := public._assert_my_delivery(p_order_id);
  if v_status <> 'Picked Up' then
    raise exception 'The ETA can only change while the order is on its way';
  end if;
  if p_eta_at is null or p_eta_at <= now() then
    raise exception 'The ETA must be in the future';
  end if;
  update public.orders set eta_at = p_eta_at where id = p_order_id;
end;
$$;

create or replace function public.delivery_mark_delivered(
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
begin
  v_status := public._assert_my_delivery(p_order_id);
  if v_status <> 'Picked Up' then
    raise exception 'Only an order on its way can be marked delivered (status "%")', v_status;
  end if;
  update public.orders
     set status       = 'Delivered',
         delivered_at = now()
   where id = p_order_id;
end;
$$;

-- The rider's own position, written to the same profiles columns v37
-- gave cashiers. Only the caller's row, only while on a delivery — the
-- app enforces the "while", the RPC enforces the "own row".
create or replace function public.delivery_update_position(
  p_latitude  double precision,
  p_longitude double precision
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_delivery() then
    raise exception 'Not authorized: delivery role required';
  end if;
  update public.profiles
     set latitude            = p_latitude,
         longitude           = p_longitude,
         location_updated_at = now()
   where id = auth.uid();
end;
$$;

-- ── 5. Closing the loop ────────────────────────────────────────────

-- The member says "I have it". Their order, in Delivered.
create or replace function public.member_confirm_received(
  p_order_id uuid
) returns void
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
end;
$$;

-- The cashier closes it. Two legitimate cases, recorded differently:
--   Agreed    → no rider was used; handed over at the counter (v48's
--               original flow). confirmation_method stays null.
--   Delivered → the member never confirmed; cashier overrides, with a
--               reason. Recorded as cashier_override so it is visible.
create or replace function public.complete_delivery_order(
  p_order_id uuid
) returns void
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
end;
$$;

-- Cancel now reaches the rider states, and always records why.
-- The rider may cancel their own delivery (member refused, address
-- unreachable); the reason is what the cashier acts on to restock.
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
  elsif public.is_staff() and (v_owner = auth.uid() or v_owner is null) then
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

-- The one-argument form v48's Dart caller still uses. Delegates.
create or replace function public.cancel_delivery_order(p_order_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  select public.cancel_delivery_order(p_order_id, null);
$$;

-- ── 6. Grants ──────────────────────────────────────────────────────
revoke all on function public.cashier_assign_rider(uuid, uuid) from public;
revoke all on function public.delivery_pickup(uuid, timestamptz) from public;
revoke all on function public.delivery_update_eta(uuid, timestamptz) from public;
revoke all on function public.delivery_mark_delivered(uuid) from public;
revoke all on function public.delivery_update_position(double precision, double precision) from public;
revoke all on function public.member_confirm_received(uuid) from public;
revoke all on function public.cancel_delivery_order(uuid, text) from public;

grant execute on function public.cashier_assign_rider(uuid, uuid) to authenticated;
grant execute on function public.delivery_pickup(uuid, timestamptz) to authenticated;
grant execute on function public.delivery_update_eta(uuid, timestamptz) to authenticated;
grant execute on function public.delivery_mark_delivered(uuid) to authenticated;
grant execute on function public.delivery_update_position(double precision, double precision) to authenticated;
grant execute on function public.member_confirm_received(uuid) to authenticated;
grant execute on function public.cancel_delivery_order(uuid, text) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (50, 'delivery_role')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='orders'
--      and column_name in ('delivery_id','eta_at','receiver_name',
--                          'confirmation_method','payment_method')
--    order by 1;                                           -- expect 5
--   select pg_get_constraintdef(oid) from pg_constraint
--    where conname = 'orders_status_check';                 -- lists 9 states
--
-- Then in the app, in this order: admin creates a rider; cashier
-- assigns them an Agreed order; rider sees it, picks up with an ETA,
-- marks delivered; member confirms. Each step must fail when done by
-- the wrong account.

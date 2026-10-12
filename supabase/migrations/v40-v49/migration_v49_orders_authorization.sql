-- ═══════════════════════════════════════════════════════════════════
-- Migration v49 — Orders: who may read, and who may move the state
--
-- v48 shipped `orders` and `order_items` with RLS OFF and six
-- SECURITY DEFINER RPCs that check nothing about the caller. As of v48:
--
--   • any signed-in member can read every other member's HOME ADDRESS
--     and GPS coordinates — every order row, every environment;
--   • cancel_delivery_order(id) cancels anyone's order, for anyone;
--   • complete_delivery_order(id) completes anyone's order;
--   • cashier_send_quote lets a member price their own order.
--
-- This is the bug class v5 closed for package upgrades ("reject
-- non-staff callers") and v43 closed for announcements. It has to be
-- fixed BEFORE a third actor (the delivery rider, v50) joins the state
-- machine — three parties on unauthorized RPCs is strictly worse than
-- two, and the checks are cheaper to write once than to retrofit.
--
-- ── Design ─────────────────────────────────────────────────────────
-- Reads are governed by RLS. Writes are NOT — there is deliberately no
-- INSERT / UPDATE / DELETE policy on either table. Every write goes
-- through a SECURITY DEFINER RPC, which bypasses RLS and therefore
-- carries its own explicit check of the caller's relation to the order:
--
--   member   — profiles.member_id = orders.member_id
--   cashier  — is_staff() and orders.cashier_id = auth.uid()
--   admin    — is_admin(), which may do anything
--
-- The absence of a write policy is the enforcement, same idiom as v36.
--
-- is_delivery() is defined here rather than in v50 so the read policy
-- can be written ONCE with its rider arm in place. Nobody has the role
-- yet, so the arm matches nothing until v50 creates the first rider.
--
-- Signatures are unchanged — every Dart caller keeps working. Only the
-- bodies gain checks, plus the state guards v48 left implicit.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_orders_authorization_v49.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── Helpers ────────────────────────────────────────────────────────

create or replace function public.is_delivery()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'delivery'
  );
$$;

-- The caller's members.id, or null for staff and riders. One place, so
-- every ownership check below reads the same way.
create or replace function public.my_member_id()
returns bigint
language sql
stable
security definer
set search_path = public
as $$
  select member_id from public.profiles where id = auth.uid();
$$;

-- Whether the caller is the rider on this order. orders.delivery_id does
-- not exist until v50, so this returns false for now; v50 replaces the
-- body. Declared here — before the policy — because a policy cannot
-- reference a function that does not exist yet.
create or replace function public.order_rider_is_me(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select false;
$$;

revoke all on function public.is_delivery() from public;
revoke all on function public.my_member_id() from public;
revoke all on function public.order_rider_is_me(uuid) from public;
grant execute on function public.is_delivery() to authenticated;
grant execute on function public.my_member_id() to authenticated;
grant execute on function public.order_rider_is_me(uuid) to authenticated;

-- ── RLS: reads ─────────────────────────────────────────────────────

alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "orders_select" on public.orders;
create policy "orders_select" on public.orders
  for select to authenticated
  using (
    public.is_admin()
    -- the member who placed it
    or member_id = public.my_member_id()
    -- the cashier working it, plus anything nobody has picked up yet
    or (public.is_staff() and (cashier_id = auth.uid() or cashier_id is null))
    -- the rider carrying it — nothing else, ever (column lands in v50;
    -- until then this arm is unreachable because nobody is a rider)
    or (public.is_delivery() and public.order_rider_is_me(id))
  );

-- order_items follow their parent: whoever can see the order can see
-- its lines. The subquery runs under the caller's own RLS, so it
-- inherits orders_select without restating it.
drop policy if exists "order_items_select" on public.order_items;
create policy "order_items_select" on public.order_items
  for select to authenticated
  using (
    exists (select 1 from public.orders o where o.id = order_items.order_id)
  );

-- No write policies on purpose. See header.

-- ── RPCs, re-declared with caller checks ───────────────────────────

-- 1. A member submits their own cart. Admins may place one on a
--    member's behalf (support); nobody else may.
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

-- 2. Cashier quotes. Staff only; a cashier may not quote as someone
--    else, and may not take over an order another cashier is already
--    pricing.
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
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required to send a quote';
  end if;
  if p_cashier_id <> auth.uid() and not public.is_admin() then
    raise exception 'Not authorized: a quote is sent under your own account';
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

-- 3. The member answers a quote. Must be their order, and there must
--    be a quote to answer.
create or replace function public.member_respond_delivery_order(
  p_order_id    uuid,
  p_action      text,
  p_counter_fee numeric
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
  if not (public.is_admin() or v_member = public.my_member_id()) then
    raise exception 'Not authorized: this is not your order';
  end if;
  if v_status <> 'Cashier Pricing & Negotiating' then
    raise exception 'There is no quote to respond to (status "%")', v_status;
  end if;

  if p_action = 'agree' then
    update public.orders
       set status      = 'Agreed',
           final_total = coalesce(items_total, 0) + coalesce(delivery_fee, 0)
     where id = p_order_id;
  elsif p_action = 'counter' then
    if p_counter_fee is null or p_counter_fee < 0 then
      raise exception 'A counter-offer needs a fee of zero or more';
    end if;
    update public.orders
       set delivery_fee = p_counter_fee,
           status       = 'Member Negotiating'
     where id = p_order_id;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end;
$$;

-- 4. The cashier answers a counter-offer. Their order, in that state.
create or replace function public.cashier_resolve_delivery_order(
  p_order_id uuid,
  p_action   text,
  p_new_fee  numeric
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
  if v_status <> 'Member Negotiating' then
    raise exception 'There is no counter-offer to resolve (status "%")', v_status;
  end if;

  if p_action = 'accept' then
    update public.orders
       set status      = 'Agreed',
           final_total = coalesce(items_total, 0) + coalesce(delivery_fee, 0)
     where id = p_order_id;
  elsif p_action = 'repropose' then
    if p_new_fee is null or p_new_fee < 0 then
      raise exception 'A new fee must be zero or more';
    end if;
    update public.orders
       set delivery_fee = p_new_fee,
           status       = 'Cashier Pricing & Negotiating'
     where id = p_order_id;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end;
$$;

-- 5. Complete. The cashier who owns it, from Agreed. (v50 widens this
--    to the post-delivery path.)
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
  if v_status <> 'Agreed' then
    raise exception 'Only an agreed order can be completed (status "%")', v_status;
  end if;

  update public.orders set status = 'Completed' where id = p_order_id;
end;
$$;

-- 6. Cancel. The member (while it is still theirs to cancel), the
--    cashier working it, or an admin. Never from a terminal state.
create or replace function public.cancel_delivery_order(
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_member bigint;
  v_owner  uuid;
begin
  select status, member_id, cashier_id into v_status, v_member, v_owner
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
    null;
  elsif public.is_staff() and (v_owner = auth.uid() or v_owner is null) then
    null;
  else
    raise exception 'Not authorized to cancel this order';
  end if;

  update public.orders set status = 'Cancelled' where id = p_order_id;
end;
$$;

-- ── Ledger ─────────────────────────────────────────────────────────
-- v47 and v48 predate the footer convention; record them here so the
-- ledger has no hole through this range.
insert into public.schema_migrations (version, name, verified, note) values
  (47, 'member_location', true, 'recorded by v49 — detected'),
  (48, 'delivery_orders', true, 'recorded by v49 — detected')
on conflict (version) do nothing;

insert into public.schema_migrations (version, name)
values (49, 'orders_authorization')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- RLS on, one select policy each, no write policies:
--   select tablename, policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename in ('orders','order_items');
--   -- expect exactly orders_select / order_items_select, both SELECT
--
-- The authorization cannot be tested here — this editor is superuser.
-- In the app: as a member, place an order, then confirm a DIFFERENT
-- member's Active Orders does not show it. As a member, try to call
-- cancel_delivery_order on an order that is not yours — it must fail.

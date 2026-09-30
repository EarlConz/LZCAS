-- ═══════════════════════════════════════════════════════════════════
-- Migration v55 — Only admins and main cashiers handle delivery orders
--
-- Requires v54 (the latest complete_delivery_order).
--
-- The client confirmed that delivery orders are the main cashier's job.
-- The app already behaves that way — only the Cashier and Admin dashboards
-- have a Delivery Orders tab, and branch cashiers get no order alerts — but
-- the database did not. Every delivery rule since v49 let in anyone who
-- passes is_staff(), and is_staff() also means INVENTORY and BRANCH
-- CASHIER (v28). Either could list unclaimed orders and price, claim,
-- dispatch, complete, cancel or remit one by calling the RPCs directly.
--
-- can_handle_orders() is the narrower check — admin or cashier, the same
-- line v51 drew for announcements — and it replaces is_staff() in:
--
--   orders_select                    (the staff arm; order_items and
--                                     order_fee_offers inherit it)
--   cashier_send_quote               (v49)
--   cashier_resolve_delivery_order   (v49)
--   cashier_assign_rider             (v50)
--   cancel_delivery_order            (v50, the staff arm)
--   cashier_remit_cod                (v52)
--   complete_delivery_order          (v54)
--
-- Each body is copied from the migration named beside it with that one
-- check changed, plus one addition in cashier_send_quote: an admin quoting
-- on someone else's behalf may only hand the order to an admin or cashier.
-- Otherwise an admin could park an order with an account that, after this
-- migration, can no longer see it.
--
-- Left on is_staff() on purpose: get_member_earnings (v52). Staff reading a
-- member's earnings is not a delivery rule, and it predates delivery.
--
-- The order-route Edge Function (v53) already accepts only admin and
-- cashier as staff. Nothing to change there.
--
-- ── Orders a branch cashier already holds ──────────────────────────
-- After this runs, an open order whose cashier_id is a branch cashier or
-- inventory account is visible to admins only. Admins can still finish or
-- cancel it. Verify query 2 lists any; expect none, since the app never
-- offered branch cashiers the page.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_delivery_cashiers_only_v55.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Who may handle delivery orders ──────────────────────────────
-- SECURITY DEFINER so it reads profiles regardless of RLS, matching
-- is_admin() / is_staff() / can_post_announcements().
create or replace function public.can_handle_orders()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and role in ('admin', 'cashier')
  );
$$;

-- ── 2. What they can see ───────────────────────────────────────────
-- v49's policy with the staff arm narrowed.
drop policy if exists "orders_select" on public.orders;
create policy "orders_select" on public.orders
  for select to authenticated
  using (
    public.is_admin()
    -- the member who placed it
    or member_id = public.my_member_id()
    -- the cashier working it, plus anything nobody has picked up yet
    or (public.can_handle_orders() and (cashier_id = auth.uid() or cashier_id is null))
    -- the rider carrying it — nothing else, ever
    or (public.is_delivery() and public.order_rider_is_me(id))
  );

-- ── 3. Quote (v49) ─────────────────────────────────────────────────
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

-- ── 4. Answer a counter-offer (v49) ────────────────────────────────
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

-- ── 5. Dispatch (v50) ──────────────────────────────────────────────
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

-- ── 6. Cancel (v50) ────────────────────────────────────────────────
-- Only the staff arm changes. The one-argument overload (v50) delegates
-- here and needs no change.
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

-- ── 7. Cash remittance (v52) ───────────────────────────────────────
create or replace function public.cashier_remit_cod(p_order_id uuid)
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

-- ── 8. Complete (v54) ──────────────────────────────────────────────
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

-- ── 9. Grants ──────────────────────────────────────────────────────
-- create or replace keeps the existing grants on the redefined RPCs. The
-- helper is new: callable by signed-in users only, like is_staff().
revoke all on function public.can_handle_orders() from public;
grant execute on function public.can_handle_orders() to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (55, 'delivery_cashiers_only')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Every delivery rule uses the new check. Expect 7 rows, all true
--    except cancel_delivery_order(p_order_id uuid) — the one-argument
--    form, which only delegates:
--      select p.proname,
--             pg_get_function_identity_arguments(p.oid) as args,
--             pg_get_functiondef(p.oid) like '%can_handle_orders()%' as narrowed
--        from pg_proc p
--       where p.pronamespace = 'public'::regnamespace
--         and p.proname in ('cashier_send_quote', 'cashier_resolve_delivery_order',
--                           'cashier_assign_rider', 'cashier_remit_cod',
--                           'complete_delivery_order', 'cancel_delivery_order')
--       order by 1, 2;
--    and the policy (expect true):
--      select qual like '%can_handle_orders()%' as narrowed
--        from pg_policies
--       where tablename = 'orders' and policyname = 'orders_select';
-- 2. Open orders held by an account that can no longer see them (expect
--    none; an admin can finish or cancel any that appear):
--      select o.id, o.status, p.role
--        from public.orders o
--        join public.profiles p on p.id = o.cashier_id
--       where p.role not in ('admin', 'cashier')
--         and o.status not in ('Completed', 'Cancelled');
-- 3. In the app:
--      • as a cashier: the Delivery Orders queue loads and an order can be
--        quoted, dispatched and completed exactly as before.
--      • a branch cashier still has no Delivery Orders tab, as before; the
--        difference is that the database now refuses them too.

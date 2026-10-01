-- ═══════════════════════════════════════════════════════════════════
-- Migration v62 — A cash code a rider can type, and busy riders for
--                 every cashier
--
-- Requires v61 (member_order_cod_code) and v52 (confirm_cod_delivery).
--
-- ── 1. Shorter cash-on-delivery code ───────────────────────────────
-- Testing (E4): the 32-character code is too long to read out and type
-- when a phone's QR will not scan. New codes are 8 characters, 0-9 and
-- A-F, shown as "AB12-CD34". That is still about 4.3 billion codes for one
-- order, valid only while that order is with its rider, and only the
-- assigned rider can try one. Typed codes are compared without dashes,
-- spaces or case, so "ab12 cd34" works too. Codes already handed out keep
-- working: the comparison treats them the same way.
--
-- ── 2. Busy riders (D5) ────────────────────────────────────────────
-- A cashier sees only their own orders and unclaimed ones (v55), so a
-- rider carrying another cashier's or an admin's order looked free.
-- delivery_busy_rider_ids() lists every rider with an order on the road,
-- whoever dispatched it, with only that order's id.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_short_cod_code_and_busy_riders_v62.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1a. The member's code (v61's body; the code generation changed) ─
create or replace function public.member_order_cod_code(p_order_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_code  text;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.member_id <> public.my_member_id() then
    raise exception 'Not authorized: this is not your order';
  end if;
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
    -- NEW (v62): 8 characters. uq_orders_cod_nonce (v52) keeps two live
    -- orders from sharing one; on that rare clash, draw again.
    loop
      v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      begin
        update public.orders
           set cod_nonce      = v_code,
               payment_method = 'cod'
         where id = p_order_id;
        exit;
      exception when unique_violation then
        null;
      end;
    end loop;
    v_order.cod_nonce := v_code;
  end if;

  return v_order.cod_nonce;
end;
$$;

-- ── 1b. The rider's check (v52's body; the comparison changed) ─────
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
  -- from a wrong one by the error it produces. NEW (v62): dashes, spaces
  -- and case do not matter.
  if v_order.cod_nonce is null
     or upper(v_order.cod_nonce)
        is distinct from upper(regexp_replace(coalesce(p_nonce, ''), '[^0-9A-Za-z]', '', 'g')) then
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

-- ── 2. Riders with an order on the road ────────────────────────────
-- One row per order on the road: the order id lets the cashier's screen
-- leave out the order it is reassigning, whose rider is not busy elsewhere.
create or replace function public.delivery_busy_rider_ids()
returns table (rider_id uuid, order_id uuid)
language sql
stable
security definer
set search_path = public
as $
  select delivery_id, id
    from public.orders
   where public.can_handle_orders()
     and delivery_id is not null
     and status in ('Assigned', 'Picked Up', 'Delivered');
$;

revoke all on function public.delivery_busy_rider_ids() from public;
grant execute on function public.delivery_busy_rider_ids() to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (62, 'short_cod_code_and_busy_riders')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. As a member, choose cash on delivery on an agreed rider order: the
--    code under the QR reads like "AB12-CD34".
-- 2. As the rider, Hand over → Enter code → type it in lower case with or
--    without the dash: the order completes.
-- 3. As a cashier, with a rider carrying an order someone else dispatched:
--    that rider shows "On a delivery" in your rider list.

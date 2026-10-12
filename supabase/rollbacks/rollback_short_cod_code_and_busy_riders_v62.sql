-- ═══════════════════════════════════════════════════════════════════
-- Rollback v62 — back to 32-character cash codes; no busy-rider list
--
-- Restores v61's member_order_cod_code and v52's confirm_cod_delivery,
-- copied verbatim, and drops delivery_busy_rider_ids().
--
-- Read first: an 8-character code already handed out still works after
-- this only if typed exactly as stored (upper case, no dash). Scanning is
-- unaffected. Roll the app back too: a v62 build asks for the busy list
-- (it copes without it) and formats codes with a dash.
-- ═══════════════════════════════════════════════════════════════════

-- v61
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

-- v52
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

drop function if exists public.delivery_busy_rider_ids();

delete from public.schema_migrations where version = 62;

notify pgrst, 'reload schema';

-- ═══════════════════════════════════════════════════════════════════
-- Rollback v55 — Only admins and main cashiers handle delivery orders
--
-- Puts back v54's behaviour: every staff account (admin, cashier,
-- inventory, branch cashier) passes the delivery rules again.
--
-- It does this by widening can_handle_orders() to is_staff()'s roles
-- rather than rewriting the seven rules v55 touched. Every one of them
-- differed from its previous version only in that check, so widening the
-- check restores them exactly. The one other v55 change — an admin may
-- only hand an order to an admin or cashier — is undone by restoring v49's
-- cashier_send_quote below.
--
-- Re-applying v55 afterwards narrows everything again.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.can_handle_orders()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_staff();
$$;

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

delete from public.schema_migrations where version = 55;

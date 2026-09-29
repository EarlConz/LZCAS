-- ═══════════════════════════════════════════════════════════════════
-- Rollback v54 — Payment rules and fee history
--
-- Restores v50's delivery_mark_delivered and v52's complete_delivery_order,
-- and removes the fee-offer history.
--
-- Read first:
--   • Orders completed at the counter since v54 keep payment_method
--     'counter'. The constraint below is restored WITHOUT 'counter' only
--     if none exist; otherwise it is left accepting it, because dropping a
--     value that rows hold would fail the rollback half way.
--   • order_fee_offers is dropped with its rows. The history cannot be
--     rebuilt afterwards — orders only ever held the current fee.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists orders_record_fee_offer on public.orders;
drop function if exists public.record_fee_offer();
drop table if exists public.order_fee_offers;

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

create or replace function public.complete_delivery_order(p_order_id uuid)
returns void
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

  perform public.order_record_sales(p_order_id);
end;
$$;

do $$
begin
  if not exists (select 1 from public.orders where payment_method = 'counter') then
    alter table public.orders drop constraint if exists orders_payment_method_check;
    alter table public.orders add constraint orders_payment_method_check
      check (payment_method is null or payment_method in ('funds', 'cod'));
  else
    raise notice 'v54 rollback: counter payments exist; payment_method still accepts ''counter''.';
  end if;
end $$;

delete from public.schema_migrations where version = 54;

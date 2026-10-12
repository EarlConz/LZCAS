-- ═══════════════════════════════════════════════════════════════════
-- Rollback v59 — No rider until the order is paid or cash is chosen
--
-- Restores v55's cashier_assign_rider (a rider can be assigned to any
-- Agreed order, paid or not) and v58's push trigger (status and rider
-- changes only). Both copied verbatim below.
--
-- Read first:
--   • The app built with v59 still disables Assign for an unpaid order
--     with no cash choice. After this rollback only that button stops the
--     cashier; roll the app back too if they need to dispatch such orders.
--   • Payments and cash choices stop sending "Ready to dispatch".
-- ═══════════════════════════════════════════════════════════════════

-- v55
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

-- v58
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
                 'order_id',        new.id,
                 'type',            lower(tg_op),
                 'old_status',      case when tg_op = 'UPDATE' then old.status end,
                 'old_delivery_id', case when tg_op = 'UPDATE' then old.delivery_id end,
                 -- Whoever made the change is not told about it.
                 'actor',           auth.uid())
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
  after update of status, delivery_id on public.orders
  for each row
  when (old.status is distinct from new.status
        or old.delivery_id is distinct from new.delivery_id)
  execute function public.queue_order_push();

revoke all on function public.queue_order_push() from public;

delete from public.schema_migrations where version = 59;

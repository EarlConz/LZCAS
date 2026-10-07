-- ═══════════════════════════════════════════════════════════════════
-- Migration v59 — No rider until the order is paid or cash is chosen
--
-- Requires v58 (the push trigger) and v55 (the latest
-- cashier_assign_rider).
--
-- ── The rule ───────────────────────────────────────────────────────
-- Until now an order could go to a rider the moment both sides agreed
-- the price, paid or not. A member who tried to pay from Balance and was
-- refused for lack of funds left an order the cashier could still
-- dispatch; the rider then found out at the door. The client wants that
-- blocked: an Agreed order is given to a rider only once it is
--   • paid (from funds; payment_status = 'paid'), or
--   • cash on delivery chosen (payment_method = 'cod', which
--     member_order_cod_code sets when the member first opens their code).
--
-- A refused funds payment leaves no trace on the order, so "tried
-- Balance and failed" and "hasn't chosen yet" look the same; both wait.
-- That was the client's choice (2026-10-01).
--
-- Unchanged:
--   • Handing over at the counter (complete_delivery_order from Agreed):
--     the member pays in person, so there is nothing to wait for.
--   • Reassigning an order already Assigned: it was dispatchable when it
--     left, and moving it to another rider changes nothing about payment.
--
-- ── Telling the cashier when it becomes dispatchable ───────────────
-- Paying and choosing cash do not change the status, so the v58 trigger
-- never fired for them and the cashier would sit waiting with no alert.
-- The trigger now also fires when payment_status or payment_method
-- changes, and sends the old values, so order-push can say "Ready to
-- dispatch" at the moment the order actually becomes so. (order-push and
-- the in-app alerts change in the same commit.)
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_dispatch_needs_payment_v59.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Dispatch (v55's body, plus the payment check) ───────────────
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

-- ── 2. The push trigger also hears payments (v58's body, plus two fields)
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

revoke all on function public.queue_order_push() from public;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (59, 'dispatch_needs_payment')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Agreed orders a rider can't be given yet (expect the unpaid ones
--    with no cash choice):
--      select id, payment_status, payment_method from public.orders
--       where status = 'Agreed'
--         and payment_status is distinct from 'paid'
--         and payment_method is distinct from 'cod';
-- 2. In the app: agree an order and don't pay. The cashier's Assign stays
--    disabled with "Waiting for … to pay". The member chooses cash on
--    delivery: the cashier gets "Ready to dispatch" and can assign.
-- 3. Deploy the order-push function from the same commit, or the payment
--    events reach an older function that ignores them (harmless, silent).

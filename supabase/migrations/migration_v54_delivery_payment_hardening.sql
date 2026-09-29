-- ═══════════════════════════════════════════════════════════════════
-- Migration v54 — Payment rules the database enforces, and the fee
--                 history the counter-offer screen needs
--
-- Requires v52 (payment, order_record_sales) and v50 (the rider states).
--
-- Three gaps, each of which the app currently guards only on the client:
--
-- ── 1. An unpaid order could be marked delivered ───────────────────
-- delivery_mark_delivered (v50) checks the rider and the status, not the
-- money. The app stopped offering it for unpaid orders — every unpaid
-- handover goes through the cash-code scan — but a client calling the RPC
-- directly could still close the door on goods nobody paid for. It now
-- refuses unless the order is paid. Cash orders never use it at all:
-- confirm_cod_delivery (v52) takes them straight to Completed.
--
-- ── 2. A counter sale recorded no payment ──────────────────────────
-- When a cashier completes an Agreed order at the counter, the member pays
-- in person — but complete_delivery_order left the order 'unpaid', so
-- reports could not tell a counter sale from an order nobody paid for,
-- and the receipt had to INFER "Paid at the counter" from the path taken.
-- It now records payment_method = 'counter', 'paid', paid_at — before the
-- sale rows are written, so `sales.payment_method` says 'counter' too.
--
-- Only the Agreed path. A Delivered order the cashier closes without the
-- member's confirmation (the override) is left exactly as paid or unpaid as
-- it was: the cashier did not take money on that path, and recording that
-- they had would be the one lie this migration exists to remove.
--
-- ── 3. The previous delivery fee was overwritten ───────────────────
-- orders.delivery_fee holds only the CURRENT offer. Once a member counters,
-- the cashier's original figure is gone, so a screen cannot show "you
-- proposed ₱80, they countered ₱50". order_fee_offers keeps every offer,
-- written by a trigger rather than by the three RPCs that set the fee:
-- rewriting cashier_send_quote, member_respond_delivery_order and
-- cashier_resolve_delivery_order would mean reproducing v49's caller checks
-- a second time to add one insert each. Who made an offer follows from the
-- status each of them sets in the SAME update as the fee — checked against
-- v49 when this was written:
--   'Member Negotiating'            → the member countered
--   'Cashier Pricing & Negotiating' → the cashier quoted or re-proposed
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_delivery_payment_hardening_v54.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. 'counter' is a way to pay ───────────────────────────────────
alter table public.orders drop constraint if exists orders_payment_method_check;
alter table public.orders add constraint orders_payment_method_check
  check (payment_method is null or payment_method in ('funds', 'cod', 'counter'));

-- ── 2. No delivered without paid ───────────────────────────────────
-- v50's body, with the payment check added after the status check.
create or replace function public.delivery_mark_delivered(
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status  text;
  v_payment text;
  v_method  text;
begin
  v_status := public._assert_my_delivery(p_order_id);
  if v_status <> 'Picked Up' then
    raise exception 'Only an order on its way can be marked delivered (status "%")', v_status;
  end if;

  select payment_status, payment_method into v_payment, v_method
    from public.orders where id = p_order_id;
  if v_payment is distinct from 'paid' then
    -- The two cases need different next steps, so they get different words.
    if v_method = 'cod' then
      raise exception 'This is a cash order: collect the payment and scan the member''s code instead';
    end if;
    raise exception 'This order has not been paid. The member can pay from their app, or choose cash and show you a code';
  end if;

  update public.orders
     set status       = 'Delivered',
         delivered_at = now()
   where id = p_order_id;
end;
$$;

-- ── 3. A counter sale records its payment ──────────────────────────
-- v52's body. The Agreed branch now marks the order paid at the counter;
-- the Delivered branch is unchanged (see the header). order_record_sales
-- still runs last, after both writes, so the sale rows carry the method.
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
  if not public.is_staff() then
    raise exception 'Not authorized: staff role required';
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

-- ── 4. Every delivery-fee offer, kept ──────────────────────────────
create table if not exists public.order_fee_offers (
  id        bigint generated always as identity primary key,
  order_id  uuid not null references public.orders (id) on delete cascade,
  fee       numeric not null,
  -- 'cashier' or 'member'. Derived from the status set alongside the fee.
  offered_by text not null check (offered_by in ('cashier', 'member')),
  offered_at timestamptz not null default now()
);

create index if not exists idx_order_fee_offers_order
  on public.order_fee_offers (order_id, offered_at);

alter table public.order_fee_offers enable row level security;

-- Readable by whoever can read the order — the same inheritance v49 uses
-- for order_items: the subquery runs under the caller's own orders policy.
-- No insert, update or delete policy: only the trigger below writes, and
-- nobody edits a price history.
drop policy if exists "order_fee_offers_select" on public.order_fee_offers;
create policy "order_fee_offers_select" on public.order_fee_offers
  for select to authenticated
  using (
    exists (select 1 from public.orders o where o.id = order_fee_offers.order_id)
  );

create or replace function public.record_fee_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.delivery_fee is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.delivery_fee is not distinct from old.delivery_fee then
    return new;
  end if;

  insert into public.order_fee_offers (order_id, fee, offered_by)
  values (
    new.id,
    new.delivery_fee,
    case when new.status = 'Member Negotiating' then 'member' else 'cashier' end
  );
  return new;
end;
$$;

drop trigger if exists orders_record_fee_offer on public.orders;
create trigger orders_record_fee_offer
  after insert or update of delivery_fee on public.orders
  for each row execute function public.record_fee_offer();

-- Orders that already have a fee get their CURRENT offer as a starting
-- row, dated from their last update. What came before it was never
-- stored and is not invented here; the screen will show one offer for
-- these, not a made-up exchange.
insert into public.order_fee_offers (order_id, fee, offered_by, offered_at)
select o.id,
       o.delivery_fee,
       case when o.status = 'Member Negotiating' then 'member' else 'cashier' end,
       coalesce(o.updated_at, o.created_at, now())
  from public.orders o
 where o.delivery_fee is not null
   and not exists (select 1 from public.order_fee_offers f where f.order_id = o.id);

-- ── 5. Grants ──────────────────────────────────────────────────────
revoke all on function public.record_fee_offer() from public;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (54, 'delivery_payment_hardening')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. 'counter' accepted:
--      select pg_get_constraintdef(oid) from pg_constraint
--       where conname = 'orders_payment_method_check';
-- 2. The history exists and backfilled:
--      select count(*) from public.order_fee_offers;
-- 3. In the app:
--      • quote an order, counter it as the member, re-propose as the
--        cashier: three rows in order_fee_offers, by cashier, member,
--        cashier.
--      • complete an unpaid Agreed order at the counter: the order and
--        its sales rows read payment_method 'counter'.
--      • as a rider, try delivery_mark_delivered on an unpaid order: it
--        is refused with the message above.

-- ═══════════════════════════════════════════════════════════════════
-- Rollback v52 — Payment, and the sale the member's confirmation
--                never recorded
--
-- Restores v50's completion RPCs and v24's get_member_earnings, and
-- drops the functions v52 introduced.
--
-- ── Read this before running it ────────────────────────────────────
-- The COLUMNS and the DATA are deliberately left in place:
--
--   • `sales` rows written by order_record_sales() are real sales of
--     real goods. Deleting them would erase revenue history and leave
--     the stock they decremented unaccounted for.
--   • Negative 'Order Payment%' rows in member_transactions are money
--     the member actually spent. Dropping them gives it back.
--
-- That has a consequence you must accept knowingly: once v24's
-- get_member_earnings is back, it no longer knows the 'Order Payment%'
-- prefixes, so any order already paid from funds STOPS being deducted
-- and those members' balances rise by what they spent. If anyone has
-- paid with funds, reconcile before rolling back:
--
--   select member_id, sum(price) as spent
--     from public.member_transactions
--    where item_name ilike 'Order Payment%'
--    group by member_id;
--
-- Roll back only together with the app build that stops calling these
-- RPCs; a client calling pay_order_with_funds after this runs gets a
-- "function does not exist" error.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Drop what v52 added ─────────────────────────────────────────
drop function if exists public.pay_order_with_funds(uuid, text);
drop function if exists public.member_order_cod_code(uuid);
drop function if exists public.confirm_cod_delivery(uuid, text);
drop function if exists public.cashier_remit_cod(uuid);

-- ── 2. Completion RPCs, back to v50 (no sale recording) ────────────
create or replace function public.member_confirm_received(p_order_id uuid)
returns void
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
end;
$$;

-- Dropped last: the two functions above must stop calling it first.
drop function if exists public.order_record_sales(uuid);

-- ── 3. get_member_earnings, back to v24 ────────────────────────────
create or replace function public.get_member_earnings(p_member_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  v_balance     integer := 0;
  v_indirect    integer := 0;
  v_passive     integer := 0;
  v_chairman    integer := 0;
  v_fridays     integer := 0;
  v_upgrade     integer := 0;
  v_total       integer := 0;
  v_earn_deduct integer := 0;
  v_bal_deduct  integer := 0;
begin
  if not (
    public.is_staff()
    or exists (
      select 1 from public.profiles pr
      where pr.id = auth.uid() and pr.member_id = p_member_id
    )
  ) then
    raise exception 'Not authorized to view these earnings';
  end if;

  select coalesce(sum(price), 0) into v_balance
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Direct Referral%';

  select coalesce(sum(price), 0) into v_indirect
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Indirect Referral%';

  select coalesce(sum(price), 0) into v_passive
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Group Sales%';

  select coalesce(sum(price), 0) into v_upgrade
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Upgrade Bonus%';

  select coalesce(sum(price), 0) into v_chairman
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Chairman Bonus%';

  v_fridays := 0;
  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

  select
    coalesce(sum(case when source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct
    from public.withdrawal_requests
    where member_id = p_member_id and status = 'approved';

  return jsonb_build_object(
    'totalEarnings',  greatest(0, v_total   - v_earn_deduct),
    'balance',        greatest(0, v_balance - v_bal_deduct),
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$function$;

-- ── 4. Columns are kept ────────────────────────────────────────────
-- See the header. To remove them anyway, knowing what goes with them:
--   drop index if exists public.uq_orders_cod_nonce;
--   alter table public.orders
--     drop column if exists paid_at,
--     drop column if exists payment_transaction_id,
--     drop column if exists cod_nonce,
--     drop column if exists sales_recorded_at,
--     drop column if exists cod_remitted_at,
--     drop column if exists cod_remitted_to;
--   alter table public.sales drop column if exists payment_method;

delete from public.schema_migrations where version = 52;

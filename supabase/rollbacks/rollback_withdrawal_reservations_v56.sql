-- ═══════════════════════════════════════════════════════════════════
-- Rollback v56 — A pending withdrawal holds its money
--
-- Removes the trigger and its helpers, and restores v52's
-- get_member_earnings and pay_order_with_funds (copied verbatim below).
--
-- Read first:
--   • Pending requests are no longer reserved: the overdraft gap v56
--     closed is open again. The 1.5.1 app-side check at approval remains.
--   • Members can once more insert a request with any status.
--   • The app built with v56 needs no rollback: when the four new
--     earnings keys are missing it treats nothing as on hold and shows
--     the full balance, exactly as before.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists withdrawal_requests_guard on public.withdrawal_requests;
drop function if exists public.guard_withdrawal_request();
drop function if exists public._member_bucket_earned(bigint, text);

-- v52
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
  v_pay_bal     integer := 0;
  v_pay_earn    integer := 0;
begin
  -- ── Authorization: staff, or the member themselves ──────────────
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

  -- NEW (v52): delivery orders paid from funds. These rows are stored
  -- NEGATIVE, so they are ADDED, not subtracted — the sign already
  -- says what they are, and a double negative here would silently pay
  -- the member for shopping.
  select coalesce(sum(price), 0) into v_pay_bal
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Order Payment (Balance)%';

  select coalesce(sum(price), 0) into v_pay_earn
    from public.member_transactions
    where member_id = p_member_id and item_name ilike 'Order Payment (Earnings)%';

  v_fridays := 0;
  v_total := v_indirect + v_passive + v_chairman + v_upgrade;

  select
    coalesce(sum(case when source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct
    from public.withdrawal_requests
    where member_id = p_member_id and status = 'approved';

  return jsonb_build_object(
    'totalEarnings',  greatest(0, v_total   + v_pay_earn - v_earn_deduct),
    'balance',        greatest(0, v_balance + v_pay_bal  - v_bal_deduct),
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays
  );
end;
$function$;

-- v52
create or replace function public.pay_order_with_funds(
  p_order_id      uuid,
  p_source_bucket text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order     public.orders%rowtype;
  v_earnings  jsonb;
  v_available numeric;
  v_label     text;
  v_txn       bigint;
begin
  if p_source_bucket not in ('total_earnings', 'balance') then
    raise exception 'Unknown source bucket "%"', p_source_bucket;
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.id is null then
    raise exception 'Order not found';
  end if;
  if v_order.member_id <> public.my_member_id() then
    raise exception 'Not authorized: this is not your order';
  end if;
  if v_order.status <> 'Agreed' then
    raise exception
      'An order can only be paid once both sides have agreed (status "%")',
      v_order.status;
  end if;
  if v_order.payment_status = 'paid' then
    raise exception 'This order is already paid';
  end if;
  if coalesce(v_order.final_total, 0) <= 0 then
    raise exception 'This order has no agreed total to pay';
  end if;

  -- The same figures the member sees on their own earnings screen:
  -- already net of approved withdrawals and of earlier order payments.
  v_earnings  := public.get_member_earnings(v_order.member_id);
  v_available := (v_earnings ->> (case
                                    when p_source_bucket = 'balance'
                                      then 'balance'
                                    else 'totalEarnings'
                                  end))::numeric;

  if v_available < v_order.final_total then
    raise exception
      'Not enough funds: % available in %, % needed',
      v_available,
      case when p_source_bucket = 'balance' then 'Balance' else 'Total Earnings' end,
      v_order.final_total;
  end if;

  -- Append-only, and prefixed so get_member_earnings (redefined below)
  -- subtracts it from the bucket it was taken from.
  v_label := case
               when p_source_bucket = 'balance'
                 then 'Order Payment (Balance)'
               else 'Order Payment (Earnings)'
             end
             || ' — Order #' || left(p_order_id::text, 8);

  insert into public.member_transactions
    (user_id, member_id, sale_id, item_id, item_name, quantity, price, timestamp)
  values
    (auth.uid(), v_order.member_id, null, null, v_label, 1,
     -round(v_order.final_total)::int, now())
  returning id into v_txn;

  update public.orders
     set payment_method         = 'funds',
         payment_status         = 'paid',
         paid_at                = now(),
         payment_transaction_id = v_txn
   where id = p_order_id;
end;
$$;

drop function if exists public._lock_member_funds(bigint);

delete from public.schema_migrations where version = 56;

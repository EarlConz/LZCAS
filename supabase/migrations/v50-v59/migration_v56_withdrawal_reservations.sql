-- ═══════════════════════════════════════════════════════════════════
-- Migration v56 — A pending withdrawal holds its money
--
-- Requires v52 (order payments; the latest get_member_earnings and
-- pay_order_with_funds).
--
-- ── The gap ────────────────────────────────────────────────────────
-- Nothing reserved a pending withdrawal. A member with ₱300 and ₱200
-- already awaiting approval could ask for up to ₱300 more, because every
-- check measured the balance as if the first request did not exist. Two
-- approvals could then pay out ₱500 against ₱300 earned, and
-- get_member_earnings clamps at zero, so the overdrawn account read ₱0
-- like any other emptied one. The audit
-- (supabase/diagnostics/audit_withdrawal_overdrafts.sql) found no case on
-- production on 2026-09-23; 1.5.1 added an app-side guard at approval.
-- This migration is the full fix that guard's comment promised.
--
-- ── The rule, enforced on the table ────────────────────────────────
-- A trigger on withdrawal_requests, so it holds for EVERY writer: the
-- app being released with this, the 1.5.1 app already installed (which
-- inserts and approves by writing the table directly), and anyone calling
-- the API by hand.
--
--   • A new pending request must fit in what is left AFTER approved
--     withdrawals AND every other pending request in the same bucket.
--   • Approving must fit in what is left after the other approved ones.
--     Pending requests are not counted against an approval: each was
--     already checked against them when it was made.
--   • A member's own insert is always a fresh pending request. Before
--     this, the insert policy checked only whose row it was, so a member
--     could save one as already 'approved'. Only an admin sets a status.
--
-- Both checks, and pay_order_with_funds, take the same per-member lock
-- first, so two requests (or a request and an order payment) arriving at
-- the same moment are checked one after the other, never side by side.
--
-- ── What members and admins see ────────────────────────────────────
-- get_member_earnings keeps every key it had, with the same values, and
-- adds pendingBalance / pendingEarnings (awaiting approval) and
-- availableBalance / availableEarnings (what can still be requested or
-- spent). The app shows the member what is on hold and caps the request
-- dialog at the available figure; the approval card shows the admin what
-- the member has left.
--
-- pay_order_with_funds now spends only the AVAILABLE figure: money a
-- member has asked to withdraw cannot also pay for an order.
--
-- ── Existing rows ──────────────────────────────────────────────────
-- Nothing is rewritten. A stacked pending request made before this can
-- still sit in the queue; approving it is refused if it would overdraw,
-- which is exactly the 1.5.1 guard, now in the database.
--
-- ── 1.5.1 approvals ────────────────────────────────────────────────
-- The 1.5.1 app writes an earnings_history snapshot BEFORE it marks the
-- request approved. If this trigger refuses the approval, that snapshot
-- is left behind. earnings_history is a display log — no balance is
-- computed from it — and 1.5.1's own guard refuses the same approvals
-- first, so in practice this does not arise. The new app approves first.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_withdrawal_reservations_v56.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. One lock per member's funds ─────────────────────────────────
-- Transaction-scoped: released at commit or rollback, never leaked. Keyed
-- on a hash so any member id fits; two members sharing a hash only wait
-- for each other, which is harmless.
create or replace function public._lock_member_funds(p_member_id bigint)
returns void
language sql
volatile
security definer
set search_path = public
as $$
  select pg_advisory_xact_lock(hashtext('member_funds'), hashtext(p_member_id::text));
$$;

-- ── 2. What a bucket has earned, before any withdrawal ─────────────
-- Summed by item_name prefix exactly as get_member_earnings does (and
-- the audit file). Order payments are stored negative, so they are added.
-- Keep these prefixes in step with get_member_earnings.
create or replace function public._member_bucket_earned(
  p_member_id bigint,
  p_bucket    text
) returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(price), 0)::integer
    from public.member_transactions
   where member_id = p_member_id
     and case
           when p_bucket = 'balance' then
                item_name ilike 'Direct Referral%'
             or item_name ilike 'Order Payment (Balance)%'
           else
                item_name ilike 'Indirect Referral%'
             or item_name ilike 'Group Sales%'
             or item_name ilike 'Upgrade Bonus%'
             or item_name ilike 'Chairman Bonus%'
             or item_name ilike 'Order Payment (Earnings)%'
         end;
$$;

-- ── 3. The rule ────────────────────────────────────────────────────
create or replace function public.guard_withdrawal_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_label    text;
  v_earned   integer;
  v_approved integer;
  v_pending  integer;
  v_left     integer;
begin
  -- Only an admin decides. (A signed-in caller who is not an admin is a
  -- member submitting; the SQL editor has no auth.uid() and is exempt.)
  if tg_op = 'INSERT'
     and auth.uid() is not null
     and not public.is_admin()
     and (new.status is distinct from 'pending'
          or new.reviewed_by is not null
          or new.reviewed_at is not null) then
    raise exception 'A new withdrawal request is always pending until an admin reviews it';
  end if;

  -- Nothing to check unless the row becomes (or changes as) pending or
  -- approved. Rejecting never needs a balance.
  if new.status not in ('pending', 'approved') then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and new.status = old.status
     and new.requested_amount = old.requested_amount
     and new.source_bucket = old.source_bucket
     and new.member_id = old.member_id then
    return new;
  end if;

  perform public._lock_member_funds(new.member_id);

  v_label := case when new.source_bucket = 'balance'
                  then 'Balance' else 'Total Earnings' end;
  v_earned := public._member_bucket_earned(new.member_id, new.source_bucket);

  -- This row itself is excluded from both sums: on an update its old
  -- state must not count against its new one.
  select
    coalesce(sum(requested_amount) filter (where status = 'approved'), 0),
    coalesce(sum(requested_amount) filter (where status = 'pending'),  0)
    into v_approved, v_pending
    from public.withdrawal_requests
   where member_id = new.member_id
     and source_bucket = new.source_bucket
     and id <> new.id;

  if new.status = 'pending' then
    v_left := v_earned - v_approved - v_pending;
    if new.requested_amount > v_left then
      if v_pending > 0 then
        raise exception
          'Only ₱% of your % can still be requested: ₱% is already awaiting approval',
          greatest(v_left, 0), v_label, v_pending;
      end if;
      raise exception
        'Only ₱% of your % can be requested', greatest(v_left, 0), v_label;
    end if;
  else
    v_left := v_earned - v_approved;
    if new.requested_amount > v_left then
      raise exception
        'Cannot approve: ₱% requested but only ₱% is left in the member''s %. Reject this request and ask them to submit a new one.',
        new.requested_amount, greatest(v_left, 0), v_label;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists withdrawal_requests_guard on public.withdrawal_requests;
create trigger withdrawal_requests_guard
  before insert or update on public.withdrawal_requests
  for each row execute function public.guard_withdrawal_request();

-- ── 4. Earnings, with what is on hold ──────────────────────────────
-- v52's function. Every existing key keeps its value; the four keys at
-- the end are new.
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
  v_earn_hold   integer := 0;
  v_bal_hold    integer := 0;
  v_earnings    integer;
  v_bal_left    integer;
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

  -- v52: delivery orders paid from funds. These rows are stored
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
    coalesce(sum(case when status = 'approved' and source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when status = 'approved' and source_bucket = 'balance'        then requested_amount else 0 end), 0),
    coalesce(sum(case when status = 'pending'  and source_bucket = 'total_earnings' then requested_amount else 0 end), 0),
    coalesce(sum(case when status = 'pending'  and source_bucket = 'balance'        then requested_amount else 0 end), 0)
    into v_earn_deduct, v_bal_deduct, v_earn_hold, v_bal_hold
    from public.withdrawal_requests
    where member_id = p_member_id and status in ('approved', 'pending');

  v_earnings := greatest(0, v_total   + v_pay_earn - v_earn_deduct);
  v_bal_left := greatest(0, v_balance + v_pay_bal  - v_bal_deduct);

  return jsonb_build_object(
    'totalEarnings',  v_earnings,
    'balance',        v_bal_left,
    'indirectBonus',  v_indirect,
    'passiveIncome',  v_passive,
    'repeatPurchase', 0,
    'chairmanBonus',  v_chairman,
    'upgradeBonus',   v_upgrade,
    'chairmanFridays', v_fridays,
    -- NEW (v56): awaiting approval, and what is left after it.
    'pendingEarnings',   v_earn_hold,
    'pendingBalance',    v_bal_hold,
    'availableEarnings', greatest(0, v_earnings - v_earn_hold),
    'availableBalance',  greatest(0, v_bal_left - v_bal_hold)
  );
end;
$function$;

-- ── 5. Order payments spend only what is not on hold ───────────────
-- v52's function. Changed: the lock, and 'available…' in place of the
-- bucket's full value.
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

  -- The same lock a withdrawal request takes: the figure read below
  -- cannot change until this payment commits.
  perform public._lock_member_funds(v_order.member_id);

  -- The same figures the member sees on their own earnings screen: net
  -- of approved withdrawals, earlier order payments, and (v56) requests
  -- still awaiting approval.
  v_earnings  := public.get_member_earnings(v_order.member_id);
  v_available := (v_earnings ->> (case
                                    when p_source_bucket = 'balance'
                                      then 'availableBalance'
                                    else 'availableEarnings'
                                  end))::numeric;

  if v_available < v_order.final_total then
    raise exception
      'Not enough funds: % available in % (after withdrawals awaiting approval), % needed',
      v_available,
      case when p_source_bucket = 'balance' then 'Balance' else 'Total Earnings' end,
      v_order.final_total;
  end if;

  -- Append-only, and prefixed so get_member_earnings subtracts it from
  -- the bucket it was taken from.
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

-- ── 6. Grants ──────────────────────────────────────────────────────
-- The helpers and the trigger function are internal: nothing outside the
-- database calls them. create or replace keeps the existing grants on
-- get_member_earnings and pay_order_with_funds.
revoke all on function public._lock_member_funds(bigint) from public;
revoke all on function public._member_bucket_earned(bigint, text) from public;
revoke all on function public.guard_withdrawal_request() from public;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (56, 'withdrawal_reservations')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. The trigger is in place (expect one row):
--      select tgname from pg_trigger
--       where tgrelid = 'public.withdrawal_requests'::regclass
--         and tgname = 'withdrawal_requests_guard';
-- 2. Earnings keep their old values and gain four keys:
--      select public.get_member_earnings(<member_id>);
--    'balance' and 'totalEarnings' must match what the app showed before.
-- 3. Run section 2 of the withdrawal audit before approving anything from
--    the existing queue: any row it lists will now be refused on approval.
-- 4. In the app, as a member with ₱300 in Balance:
--      • request ₱200: accepted. The dialog now says ₱100 available.
--      • request ₱101: refused — "Only ₱100 of your Balance can still be
--        requested: ₱200 is already awaiting approval".
--      • request ₱100: accepted. Both requests approve.

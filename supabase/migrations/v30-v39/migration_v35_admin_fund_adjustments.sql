-- ═══════════════════════════════════════════════════════════════════
-- Migration v35 — Admin-adjustable member funds (with a required reason)
--
-- Until now the only way to correct a member's earnings was to hand-write
-- rows in the SQL editor (as was done for member 22: −₱300 Direct Referral,
-- −₱50 Chairman Bonus). This migration makes that an auditable, admin-only
-- feature of the app.
--
-- ── The rule this MUST obey ────────────────────────────────────────
-- Earnings are a FROZEN, APPEND-ONLY ledger. `get_member_earnings` (v24)
-- sums `member_transactions` by `item_name` prefix; nothing recomputes.
-- So an adjustment is NEVER an UPDATE or DELETE of an existing credit —
-- it is a NEW row carrying the difference:
--
--     item_name = 'Chairman Bonus Adjustment — <reason>'
--     price     = -50
--
-- That still matches `ilike 'Chairman Bonus%'`, so the totals move on their
-- own with no change to the earnings RPC, and the original credit remains
-- intact and reconcilable. The reason lives IN `item_name` because that is
-- the string the member's "Sources" list renders.
--
-- Four parts:
--   1. earnings_history.note — snapshots stored deltas with no cause, which
--      is why a decrease used to be mislabelled "Withdrawal".
--   2. fund_adjustments — audit trail (who, when, why) that does not depend
--      on parsing item_name.
--   3. admin_adjust_member_funds() — the only supported write path.
--   4. get_member_earnings_sources() — v34 + an `is_adjustment` flag.
--
-- Safe on live: changes no existing row and no existing policy. Adding a
-- column to the v34 function's result is backward-compatible — older clients
-- read by key and simply ignore it.
--
-- Rollback: supabase/rollbacks/rollback_admin_fund_adjustments_v35.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. A cause for every snapshot ──────────────────────────────────
-- earnings_history rows record WHAT changed (deltas) but never WHY. The
-- member dashboard therefore had to guess, and guessed "Withdrawal" for
-- any decrease. An adjustment writes its reason here so History can state
-- the actual cause.
alter table public.earnings_history
  add column if not exists note text;

-- ── 2. Audit trail ─────────────────────────────────────────────────
-- Deliberately separate from member_transactions: that table is the money,
-- this table is the paperwork. Keeping them apart means the audit log can
-- record the acting admin, the before/after figures and the untruncated
-- reason without any of it affecting a sum.
create table if not exists public.fund_adjustments (
  id             bigint generated always as identity primary key,
  member_id      bigint      not null,
  bucket         text        not null,   -- 'chairman_bonus', 'direct_referral', …
  amount         integer     not null,   -- signed: negative deducts
  reason         text        not null,
  -- The member_transactions row this created. The link is what lets the
  -- sources RPC flag a row as an adjustment without sniffing its label.
  transaction_id bigint,
  balance_before integer     not null default 0,  -- of THIS bucket
  balance_after  integer     not null default 0,
  adjusted_by    uuid        not null,   -- auth.uid() of the acting admin
  created_at     timestamptz not null default now()
);

create index if not exists idx_fund_adjustments_member
  on public.fund_adjustments (member_id, created_at desc);

create index if not exists idx_fund_adjustments_txn
  on public.fund_adjustments (transaction_id);

alter table public.fund_adjustments enable row level security;

-- Admins read the log. Nobody writes directly — the SECURITY DEFINER
-- function below is the only path in, so the audit row can never be
-- omitted or forged independently of the ledger row it describes.
drop policy if exists "fund_adjustments_select_admin" on public.fund_adjustments;
create policy "fund_adjustments_select_admin" on public.fund_adjustments
  for select to authenticated
  using (public.is_admin());

-- ── 3. The one supported write path ────────────────────────────────
create or replace function public.admin_adjust_member_funds(
  p_member_id bigint,
  p_bucket    text,
  p_amount    integer,
  p_reason    text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason  text := btrim(coalesce(p_reason, ''));
  v_bucket  text := lower(btrim(coalesce(p_bucket, '')));
  v_prefix  text;
  v_label   text;
  v_current integer;
  v_new     integer;
  v_txn_id  bigint;
  v_before  jsonb;
  v_after   jsonb;
  v_last    record;
begin
  -- ── Authorization: admins only ────────────────────────────────
  -- Stricter than the rest of the earnings RPCs, which accept any staff
  -- role. Cashiers sell; only an admin moves money that was already
  -- earned.
  if not public.is_admin() then
    raise exception 'Only an administrator can adjust member funds';
  end if;

  if p_amount is null or p_amount = 0 then
    raise exception 'Enter an amount to add or deduct';
  end if;

  if length(v_reason) < 3 then
    raise exception 'A reason is required for every fund adjustment';
  end if;

  -- The reason ends up inside item_name, which renders as a single line in
  -- the member's earnings list — collapse whitespace and cap the length so
  -- one long paste cannot wreck that row. The audit table keeps the full text.
  v_reason := left(regexp_replace(v_reason, '\s+', ' ', 'g'), 120);

  -- Bucket → the item_name prefix get_member_earnings already sums by.
  -- This mapping is the whole trick: matching the prefix is what makes the
  -- totals move without touching the earnings RPC.
  v_prefix := case v_bucket
    when 'direct_referral'   then 'Direct Referral'
    when 'indirect_referral' then 'Indirect Referral'
    when 'group_sales'       then 'Group Sales'
    when 'chairman_bonus'    then 'Chairman Bonus'
    when 'upgrade_bonus'     then 'Upgrade Bonus'
    else null
  end;

  if v_prefix is null then
    raise exception 'Unknown fund type: %', p_bucket;
  end if;

  if not exists (select 1 from public.members where id = p_member_id) then
    raise exception 'Member % no longer exists', p_member_id;
  end if;

  -- ── Guard: never drive a bucket negative ──────────────────────
  -- get_member_earnings clamps the displayed total at 0, so a bucket that
  -- went negative would silently absorb later legitimate earnings instead
  -- of showing them. Refuse rather than create that trap.
  select coalesce(sum(price), 0) into v_current
    from public.member_transactions
   where member_id = p_member_id
     and item_name ilike v_prefix || '%';

  v_new := v_current + p_amount;
  if v_new < 0 then
    raise exception
      '% is only %; deducting % would leave it below zero',
      v_prefix, v_current, abs(p_amount);
  end if;

  v_before := public.get_member_earnings(p_member_id);

  -- ── The ledger row: append-only, never an UPDATE ──────────────
  v_label := v_prefix || ' Adjustment — ' || v_reason;

  insert into public.member_transactions
    (user_id, member_id, item_id, sale_id, item_name, quantity, price, timestamp)
  values
    (auth.uid(), p_member_id, null, null, v_label, 0, p_amount, now())
  returning id into v_txn_id;

  insert into public.fund_adjustments
    (member_id, bucket, amount, reason, transaction_id,
     balance_before, balance_after, adjusted_by)
  values
    (p_member_id, v_bucket, p_amount, btrim(coalesce(p_reason, '')), v_txn_id,
     v_current, v_new, auth.uid());

  -- ── Snapshot, so the member's History explains the change ─────
  -- Normally the member's own dashboard writes these on next open. Doing it
  -- here means the entry (and its reason) exists the moment the admin acts,
  -- rather than appearing later with no cause attached.
  v_after := public.get_member_earnings(p_member_id);

  select total_earnings, balance
    into v_last
    from public.earnings_history
   where member_id = p_member_id
   order by recorded_at desc
   limit 1;

  insert into public.earnings_history (
    member_id, total_earnings, balance,
    earnings_delta, balance_delta,
    indirect_bonus, group_sales, passive_income,
    repeat_purchase, chairman_bonus, upgrade_bonus, note
  ) values (
    p_member_id,
    (v_after->>'totalEarnings')::integer,
    (v_after->>'balance')::integer,
    (v_after->>'totalEarnings')::integer - coalesce(v_last.total_earnings, 0),
    (v_after->>'balance')::integer       - coalesce(v_last.balance, 0),
    (v_after->>'indirectBonus')::integer,
    0,  -- matches what the client writes: get_member_earnings has no
        -- 'groupSales' key, passive income carries that figure
    (v_after->>'passiveIncome')::integer,
    (v_after->>'repeatPurchase')::integer,
    (v_after->>'chairmanBonus')::integer,
    (v_after->>'upgradeBonus')::integer,
    v_label
  );

  return jsonb_build_object(
    'transactionId', v_txn_id,
    'bucket',        v_bucket,
    'label',         v_label,
    'amount',        p_amount,
    'bucketBefore',  v_current,
    'bucketAfter',   v_new,
    'before',        v_before,
    'after',         v_after
  );
end;
$$;

grant execute on function
  public.admin_adjust_member_funds(bigint, text, integer, text)
  to authenticated;

-- ── 4. Sources RPC — v34 plus an `is_adjustment` flag ──────────────
-- Two reasons the flag is needed:
--   • The UI styles an adjustment differently from an earned credit.
--   • 'Upgrade Bonus — Ambassador' encodes the target tier after the dash,
--     which the client parses into "Upgraded to Ambassador". An
--     'Upgrade Bonus Adjustment — <reason>' row has the same shape, and
--     without this flag would read "Upgraded to <reason>".
-- Joined from fund_adjustments rather than sniffed from the label, so it
-- stays correct even if the label format is ever changed.
--
-- The return type changes, so the old function must be dropped first —
-- CREATE OR REPLACE cannot alter a function's OUT columns.
drop function if exists public.get_member_earnings_sources(bigint);

create or replace function public.get_member_earnings_sources(
  p_member_id bigint
)
returns table (
  label         text,
  amount        integer,
  quantity      integer,
  occurred_at   timestamptz,
  source_name   text,
  sale_item     text,
  is_adjustment boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
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

  return query
  select
    mt.item_name::text                                  as label,
    coalesce(mt.price, 0)::integer                      as amount,
    coalesce(mt.quantity, 0)::integer                   as quantity,
    mt."timestamp"                                      as occurred_at,
    (case
       -- An adjustment has no counterparty; its label IS the explanation.
       when fa.id is not null then null
       when mt.item_name ilike 'Group Sales%'
         then nullif(btrim(coalesce(s.buyer_name, '')), '')
       when mt.item_name ilike 'Direct Referral%'
         or mt.item_name ilike 'Indirect Referral%'
         or mt.item_name ilike 'Chairman Bonus%'
         then nullif(
                btrim(concat_ws(' ', m.first_name, m.last_name)), '')
       else null
     end)::text                                         as source_name,
    (case
       when fa.id is null and mt.item_name ilike 'Group Sales%'
         then nullif(btrim(coalesce(s.item_name, '')), '')
       else null
     end)::text                                         as sale_item,
    (fa.id is not null)                                 as is_adjustment
  from public.member_transactions mt
  left join public.members m on m.id = mt.item_id
  left join public.sales   s on s.id = mt.sale_id
  left join public.fund_adjustments fa on fa.transaction_id = mt.id
  where mt.member_id = p_member_id
  order by mt."timestamp" desc;
end;
$$;

grant execute on function public.get_member_earnings_sources(bigint)
  to authenticated;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Columns and table exist:
--      select column_name from information_schema.columns
--       where table_name = 'earnings_history' and column_name = 'note';
--      select count(*) from public.fund_adjustments;
--
-- 2. The functions exist with the right shapes:
--      select p.proname, pg_get_function_identity_arguments(p.oid)
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--       where n.nspname = 'public'
--         and p.proname in ('admin_adjust_member_funds',
--                           'get_member_earnings_sources');
--
-- 3. In the SQL editor auth.uid() is null, so a bare call correctly raises
--    "Only an administrator can adjust member funds". To exercise it for
--    real, impersonate an admin:
--
--      set local role authenticated;
--      set local request.jwt.claims = '{"sub":"<admin auth uuid>"}';
--      select public.admin_adjust_member_funds(22, 'chairman_bonus', -50,
--                                              'Duplicate referral reversed');
--
--    Expect bucketBefore/bucketAfter to differ by the amount, one new
--    member_transactions row, one fund_adjustments row, and one
--    earnings_history row whose note carries the reason.

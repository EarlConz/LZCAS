-- ═══════════════════════════════════════════════════════════════════
-- AUDIT WITHDRAWAL OVERDRAFTS (read-only — writes nothing)
--
-- Answers one question: has anyone been approved for more than they
-- earned, and is anyone queued up to be?
--
-- ── Why this can happen ────────────────────────────────────────────
-- Nothing reserves a pending request. The member's dialog validates
-- against the CURRENT balance, so with ₱300 earned and ₱200 already
-- awaiting approval, a second request for up to ₱300 is accepted. The
-- admin approval screen shows neither the balance nor the member's other
-- pending rows, so both can be approved.
--
-- `get_member_earnings` (v24) then reports
--   greatest(0, earned - sum(approved))
-- so an overdrawn account displays a balance of 0, exactly like a member
-- who withdrew precisely what they earned. No screen in the app shows the
-- difference. This file is the only way to see it.
--
-- The amounts below are the AUTHORISED payout against the EARNED total.
-- Whether the cash actually left the till is a question for whoever
-- handles payouts — this reconciles the records, not the drawer.
--
-- ── How to run ─────────────────────────────────────────────────────
-- RUN EACH NUMBERED SECTION ON ITS OWN (highlight it, then Run). The
-- Supabase editor shows only the last statement's result, so running the
-- whole file at once would hide sections 1 and 2. Each section is
-- self-contained and they can be run in any order.
-- ═══════════════════════════════════════════════════════════════════


-- ═══ 1. ALREADY OVERDRAWN ══════════════════════════════════════════
-- Approved payouts exceed what the member earned. Every row here is
-- money the records say was authorised and never backed.
-- AN EMPTY RESULT IS THE ANSWER YOU WANT.

with earned as (
  -- Summed exactly the way get_member_earnings does: by item_name
  -- prefix, which also picks up the v35 admin adjustments.
  select
    m.id                                     as member_id,
    trim(m.first_name || ' ' || m.last_name) as member_name,
    m.role,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Direct Referral%'), 0)   as balance_earned,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Indirect Referral%'
         or t.item_name ilike 'Group Sales%'
         or t.item_name ilike 'Upgrade Bonus%'
         or t.item_name ilike 'Chairman Bonus%'), 0)    as earnings_earned
  from public.members m
  left join public.member_transactions t on t.member_id = m.id
  where m.is_deleted = false
  group by m.id, m.first_name, m.last_name, m.role
),
approved as (
  select
    member_id,
    coalesce(sum(requested_amount) filter (
      where source_bucket = 'balance'), 0)        as bal_approved,
    coalesce(sum(requested_amount) filter (
      where source_bucket = 'total_earnings'), 0) as earn_approved
  from public.withdrawal_requests
  where status = 'approved'
  group by member_id
)
select
  e.member_id,
  e.member_name,
  e.role,
  'balance'                         as bucket,
  e.balance_earned                  as earned,
  a.bal_approved                    as approved,
  a.bal_approved - e.balance_earned as over_by
from earned e
join approved a on a.member_id = e.member_id
where a.bal_approved > e.balance_earned

union all

select
  e.member_id,
  e.member_name,
  e.role,
  'total_earnings',
  e.earnings_earned,
  a.earn_approved,
  a.earn_approved - e.earnings_earned
from earned e
join approved a on a.member_id = e.member_id
where a.earn_approved > e.earnings_earned

order by over_by desc;


-- ═══ 2. EXPOSURE RIGHT NOW ═════════════════════════════════════════
-- Pending requests that WOULD overdraw the account if approved. Reject
-- or trim these before approving anything.

with earned as (
  select
    m.id                                     as member_id,
    trim(m.first_name || ' ' || m.last_name) as member_name,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Direct Referral%'), 0)   as balance_earned,
    coalesce(sum(t.price) filter (
      where t.item_name ilike 'Indirect Referral%'
         or t.item_name ilike 'Group Sales%'
         or t.item_name ilike 'Upgrade Bonus%'
         or t.item_name ilike 'Chairman Bonus%'), 0)    as earnings_earned
  from public.members m
  left join public.member_transactions t on t.member_id = m.id
  where m.is_deleted = false
  group by m.id, m.first_name, m.last_name
),
req as (
  select
    member_id,
    coalesce(sum(requested_amount) filter (
      where status = 'approved' and source_bucket = 'balance'), 0)        as bal_approved,
    coalesce(sum(requested_amount) filter (
      where status = 'approved' and source_bucket = 'total_earnings'), 0) as earn_approved,
    coalesce(sum(requested_amount) filter (
      where status = 'pending'  and source_bucket = 'balance'), 0)        as bal_pending,
    coalesce(sum(requested_amount) filter (
      where status = 'pending'  and source_bucket = 'total_earnings'), 0) as earn_pending
  from public.withdrawal_requests
  group by member_id
)
select
  e.member_id,
  e.member_name,
  'balance'                                           as bucket,
  e.balance_earned                                    as earned,
  r.bal_approved                                      as already_approved,
  r.bal_pending                                       as pending,
  (r.bal_approved + r.bal_pending) - e.balance_earned as would_be_over_by
from earned e
join req r on r.member_id = e.member_id
where r.bal_pending > 0
  and (r.bal_approved + r.bal_pending) > e.balance_earned

union all

select
  e.member_id,
  e.member_name,
  'total_earnings',
  e.earnings_earned,
  r.earn_approved,
  r.earn_pending,
  (r.earn_approved + r.earn_pending) - e.earnings_earned
from earned e
join req r on r.member_id = e.member_id
where r.earn_pending > 0
  and (r.earn_approved + r.earn_pending) > e.earnings_earned

order by would_be_over_by desc;


-- ═══ 3. STACKED REQUESTS ═══════════════════════════════════════════
-- More than one pending request in the same bucket. Not wrong in itself
-- — a member may simply have asked twice — but it is the shape the
-- overdraft arrives in, and worth a look whether or not section 2 fires.

select
  w.member_id,
  trim(m.first_name || ' ' || m.last_name) as member_name,
  w.source_bucket,
  count(*)                                 as pending_requests,
  sum(w.requested_amount)                  as pending_total,
  min(w.created_at)                        as first_requested,
  max(w.created_at)                        as last_requested
from public.withdrawal_requests w
join public.members m on m.id = w.member_id
where w.status = 'pending'
group by w.member_id, m.first_name, m.last_name, w.source_bucket
having count(*) > 1
order by pending_total desc;

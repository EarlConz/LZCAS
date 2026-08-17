-- ═══════════════════════════════════════════════════════════════════
-- Migration v34 — Itemised earnings sources ("who did this come from?")
--
-- The member dashboard lists each earning credit with the person it came
-- from. Resolving those names client-side does NOT work: RLS deliberately
-- limits a member to their OWN rows —
--   members_select : is_staff() OR id = my member_id
--   sales_select   : is_staff() OR buyer_id = my member_id
-- so a reseller cannot read their downline's names or their downline's
-- purchases. The lookups return zero rows (silently, since RLS filters
-- rather than errors) and every entry renders as "Source not recorded".
--
-- Fix: resolve the names HERE, in one SECURITY DEFINER function that runs
-- with table-owner rights — the same pattern (and the same authorization
-- check) as get_member_earnings. RLS stays untouched and just as strict;
-- the member only ever learns the names attached to their own ledger.
--
-- Attribution, by row type:
--   • Direct / Indirect Referral, Chairman Bonus → item_id is the REFERRED
--     member's id (set by the v20/v24 triggers)
--   • Group Sales (Direct/Indirect) → sale_id → the sale's stored buyer
--   • Upgrade Bonus → no link is recorded; source_name is null and the UI
--     falls back to the label, which names the target tier
--
-- Read-only. Adds one function; changes no data and no policies.
-- Rollback: supabase/rollbacks/rollback_earnings_sources_v34.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.get_member_earnings_sources(
  p_member_id bigint
)
returns table (
  label       text,
  amount      integer,
  quantity    integer,
  occurred_at timestamptz,
  source_name text,
  sale_item   text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  -- ── Authorization: staff, or the member themselves ──────────────
  -- Mirrors get_member_earnings so this can never expose one member's
  -- ledger (or their downline's names) to another member.
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
       when mt.item_name ilike 'Group Sales%'
         then nullif(btrim(coalesce(s.item_name, '')), '')
       else null
     end)::text                                         as sale_item
  from public.member_transactions mt
  left join public.members m on m.id = mt.item_id
  left join public.sales   s on s.id = mt.sale_id
  where mt.member_id = p_member_id
  order by mt."timestamp" desc;
end;
$$;

grant execute on function public.get_member_earnings_sources(bigint)
  to authenticated;

-- ── Verify ─────────────────────────────────────────────────────────
-- In the SQL editor auth.uid() is null, so this raises "Not authorized"
-- unless you impersonate. To check a real member, run:
--
--   set local role authenticated;
--   set local request.jwt.claims = '{"sub":"<the auth user uuid>"}';
--   select * from public.get_member_earnings_sources(<member id>);
--
-- Expect source_name populated for referral/chairman/group-sales rows.

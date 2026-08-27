-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration v35 — Admin-adjustable member funds
--
-- Removes the write path and restores the v34 sources RPC.
--
-- ⚠️ This does NOT reverse any adjustment that was already made. Those are
-- rows in `member_transactions`, and they are real money — the whole point
-- of the append-only design is that nothing silently deletes them. To undo
-- an individual adjustment, post the opposite one; to see what was posted,
-- read `fund_adjustments` BEFORE running part 3 below.
--
--   select fa.created_at, fa.member_id, fa.bucket, fa.amount, fa.reason,
--          fa.transaction_id
--     from public.fund_adjustments fa
--    order by fa.created_at desc;
--
-- Parts 1 and 2 are safe and lose nothing. Part 3 is destructive and is
-- commented out on purpose.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Remove the write path ───────────────────────────────────────
drop function if exists
  public.admin_adjust_member_funds(bigint, text, integer, text);

-- ── 2. Restore the v34 sources RPC (no is_adjustment column) ───────
drop function if exists public.get_member_earnings_sources(bigint);

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

-- ── 3. DESTRUCTIVE — drops the audit trail and the snapshot reasons ─
-- Leave these commented unless you are certain. Keeping the table and the
-- column costs nothing and preserves the record of every adjustment made
-- while v35 was live.
--
-- drop table if exists public.fund_adjustments;
-- alter table public.earnings_history drop column if exists note;

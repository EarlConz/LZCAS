-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v27_chairman_min_tier.sql
--
-- Restores v25 Chairman behavior: Chairman = the EARNER's OWN package rate per
-- qualifying direct referral (NOT min-tier). Direct/Indirect/Upgrade are
-- untouched. Two parts, mirroring v27:
--   1. Redefine the availment trigger so its chairman inserts use the earner's
--      own rate again.
--   2. Recompute the Chairman ledger at the earner's own rate (historical).
--
-- The referral_bonus_min_tier helper keeps its 'chairman' branch — harmless
-- (this restored trigger/backfill doesn't use it).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Trigger — chairman inserts back to earner's own rate (v25) ────
create or replace function public.crystallize_referral_on_availment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.package_id is null then
    return NEW;
  end if;

  if exists (
    select 1 from public.sales s
    where s.buyer_id = NEW.buyer_id
      and s.package_id is not null
      and s.id <> NEW.id
      and (s."timestamp" < NEW."timestamp"
           or (s."timestamp" = NEW."timestamp" and s.id < NEW.id))
  ) then
    return NEW;
  end if;

  -- ═══ SIDE R ═══
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a1.user_id, a1.id, NEW.buyer_id, 'Direct Referral', 1,
         public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'direct'),
         NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  where m.id = NEW.buyer_id
    and a1.is_deleted = false
    and a1.package_id is not null
    and public.referral_bonus_min_tier(a1.package_id, NEW.package_id, 'direct') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a1.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Direct Referral%');

  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a1.user_id, a1.id, NEW.buyer_id, 'Chairman Bonus', 1,
         pk.chairmans_bonus, NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  join public.packages pk on pk.id = a1.package_id
  where m.id = NEW.buyer_id
    and a1.is_deleted = false
    and pk.chairmans_bonus > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a1.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Chairman Bonus%');

  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select a2.user_id, a2.id, NEW.buyer_id, 'Indirect Referral', 1,
         public.referral_bonus_min_tier(a2.package_id, NEW.package_id, 'indirect'),
         NEW."timestamp"
  from public.members m
  join public.members a1 on a1.id = m.referrer_id
  join public.members a2 on a2.id = a1.referrer_id
  where m.id = NEW.buyer_id
    and a2.is_deleted = false
    and a2.package_id is not null
    and public.referral_bonus_min_tier(a2.package_id, NEW.package_id, 'indirect') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = a2.id and t.item_id = NEW.buyer_id
                      and t.item_name ilike 'Indirect Referral%');

  -- ═══ SIDE A (catch-up) ═══
  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, d.id, 'Direct Referral', 1,
         public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'direct'),
         NEW."timestamp"
  from public.members m
  join public.members d on d.referrer_id = NEW.buyer_id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and public.first_availed_package(d.id) is not null
    and public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(d.id), 'direct') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = d.id
                      and t.item_name ilike 'Direct Referral%');

  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, d.id, 'Chairman Bonus', 1,
         pk.chairmans_bonus, NEW."timestamp"
  from public.members m
  join public.packages pk on pk.id = NEW.package_id
  join public.members d on d.referrer_id = NEW.buyer_id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and pk.chairmans_bonus > 0
    and public.first_availed_package(d.id) is not null
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = d.id
                      and t.item_name ilike 'Chairman Bonus%');

  insert into public.member_transactions
    (user_id, member_id, item_id, item_name, quantity, price, timestamp)
  select m.user_id, NEW.buyer_id, e.id, 'Indirect Referral', 1,
         public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(e.id), 'indirect'),
         NEW."timestamp"
  from public.members m
  join public.members d on d.referrer_id = NEW.buyer_id
  join public.members e on e.referrer_id = d.id
  where m.id = NEW.buyer_id
    and d.is_deleted = false
    and e.is_deleted = false
    and public.first_availed_package(e.id) is not null
    and public.referral_bonus_min_tier(NEW.package_id, public.first_availed_package(e.id), 'indirect') > 0
    and not exists (select 1 from public.member_transactions t
                    where t.member_id = NEW.buyer_id and t.item_id = e.id
                      and t.item_name ilike 'Indirect Referral%');

  return NEW;
end;
$$;

drop trigger if exists trg_crystallize_referral_on_availment on public.sales;
create trigger trg_crystallize_referral_on_availment
  after insert on public.sales
  for each row execute function public.crystallize_referral_on_availment();

-- ── 2. Recompute Chairman ledger at the earner's OWN rate (v25) ──────
delete from public.member_transactions where item_name ilike 'Chairman Bonus%';

with pairs as (
  select a1.id as earner_id, a1.user_id as earner_user, x.id as ref_id,
         greatest(public.first_availment_ts(a1.id), public.first_availment_ts(x.id)) as cts
  from public.members x
  join public.members a1 on a1.id = x.referrer_id
  where x.is_deleted = false and a1.is_deleted = false
    and public.first_availed_package(x.id) is not null
    and public.first_availment_ts(a1.id) is not null
),
priced as (
  select p.*,
         coalesce((select pk.chairmans_bonus from public.packages pk
                   where pk.id = public.package_held_at(p.earner_id, p.cts)), 0) as chair
  from pairs p
)
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select earner_user, earner_id, ref_id, 'Chairman Bonus', 1, chair, cts
from priced
where chair > 0;

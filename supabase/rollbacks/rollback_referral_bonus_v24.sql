-- ═══════════════════════════════════════════════════════════════════
-- ROLLBACK for migration_v25_referral_availment_based.sql
--
-- Restores the v24 behavior: Direct/Indirect/Chairman bonuses are written at
-- member REGISTRATION, at the earner's own package rate, with no availment
-- gating and no min-tier cap. Three parts:
--   1. Drop the v25 availment trigger.
--   2. Restore the v24 registration trigger + function.
--   3. Rebuild the ledger under the v24 rule.
--
-- Amounts use the earner's CURRENT package rate (the exact historical frozen
-- rate at each registration can't be reconstructed). The RPC is unchanged.
-- The helper functions first_availed_package / referral_bonus_min_tier are
-- left in place (harmless); drop them manually if you want them gone.
--
-- If you took a pre-v25 snapshot, the cleanest restore is instead:
--     truncate public.member_transactions;
--     insert into public.member_transactions
--       select * from member_transactions_backup_v25;
--   then run this file's parts 1–2 (triggers) but SKIP part 3 (the rebuild).
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Remove the v25 availment trigger ──────────────────────────────
drop trigger if exists trg_crystallize_referral_on_availment on public.sales;

-- ── 2. Restore the v24 registration trigger (Direct + Chairman + Indirect)
create or replace function public.record_referral_bonus_on_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_l2       bigint;
  v_direct   integer;
  v_chairman integer;
  v_indirect integer;
begin
  if NEW.referrer_id is null then
    return NEW;
  end if;

  select coalesce(p.direct_referral_bonus, 0), coalesce(p.chairmans_bonus, 0)
    into v_direct, v_chairman
    from public.members m
    left join public.packages p on p.id = m.package_id
    where m.id = NEW.referrer_id;

  if coalesce(v_direct, 0) > 0 then
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    values
      (NEW.user_id, NEW.referrer_id, NEW.id, 'Direct Referral', 1, v_direct, now());
  end if;

  if coalesce(v_chairman, 0) > 0 then
    insert into public.member_transactions
      (user_id, member_id, item_id, item_name, quantity, price, timestamp)
    values
      (NEW.user_id, NEW.referrer_id, NEW.id, 'Chairman Bonus', 1, v_chairman, now());
  end if;

  select referrer_id into v_l2 from public.members where id = NEW.referrer_id;
  if v_l2 is not null then
    select coalesce(p.indirect_referral_bonus, 0) into v_indirect
      from public.members m
      left join public.packages p on p.id = m.package_id
      where m.id = v_l2;

    if coalesce(v_indirect, 0) > 0 then
      insert into public.member_transactions
        (user_id, member_id, item_id, item_name, quantity, price, timestamp)
      values
        (NEW.user_id, v_l2, NEW.id, 'Indirect Referral', 1, v_indirect, now());
    end if;
  end if;

  return NEW;
end;
$$;

drop trigger if exists trg_record_referral_bonus on public.members;
create trigger trg_record_referral_bonus
  after insert on public.members
  for each row execute function public.record_referral_bonus_on_member();

-- ── 3. Rebuild the ledger under the v24 rule (skip if restoring a snapshot) ──
delete from public.member_transactions
where item_name ilike 'Direct Referral%'
   or item_name ilike 'Indirect Referral%'
   or item_name ilike 'Chairman Bonus%';

-- Direct — every member with a referrer who holds a package, at the referrer's OWN rate
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select a1.user_id, a1.id, m.id, 'Direct Referral', 1, pk.direct_referral_bonus, now()
from public.members m
join public.members a1 on a1.id = m.referrer_id
join public.packages pk on pk.id = a1.package_id
where m.is_deleted = false and a1.is_deleted = false and pk.direct_referral_bonus > 0;

-- Chairman — referrer's own chairman rate, one per referral
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select a1.user_id, a1.id, m.id, 'Chairman Bonus', 1, pk.chairmans_bonus, now()
from public.members m
join public.members a1 on a1.id = m.referrer_id
join public.packages pk on pk.id = a1.package_id
where m.is_deleted = false and a1.is_deleted = false and pk.chairmans_bonus > 0;

-- Indirect — referrer's referrer's own indirect rate
insert into public.member_transactions
  (user_id, member_id, item_id, item_name, quantity, price, timestamp)
select a2.user_id, a2.id, m.id, 'Indirect Referral', 1, pk2.indirect_referral_bonus, now()
from public.members m
join public.members a1 on a1.id = m.referrer_id
join public.members a2 on a2.id = a1.referrer_id
join public.packages pk2 on pk2.id = a2.package_id
where m.is_deleted = false and a2.is_deleted = false and pk2.indirect_referral_bonus > 0;

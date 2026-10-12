-- ═══════════════════════════════════════════════════════════════════
-- Migration v67 — A member's referrer can't be someone they referred
--
-- Requires nothing new. Safe to re-run.
--
-- Found 2026-10-03 (staging members 3 and 6; test X6): Edit Member let a
-- member pick their own downline as referrer. With A → B and then B → A,
-- each appears as the other's direct referral and as their OWN indirect
-- one, and the commission triggers walk the loop: a member is paid Group
-- Sales on their own purchases (v19) and referral bonuses on their own
-- package (v25–v27). The client's rule: "if B is already the direct
-- referral of A, B shouldn't be able to make A his direct referral."
--
-- A trigger on members now refuses, on insert or when referrer_id
-- changes:
--   • a member as their own referrer;
--   • a referrer who is anywhere below the member (their direct referral,
--     that one's referral, and so on).
-- The app hides those choices too (Edit Member); this is the backstop.
--
-- Existing loops are NOT changed and do not block other edits: the check
-- runs only when referrer_id actually changes. Production has none
-- (audit_referral_loops.sql, section 5); staging's are cleaned up by hand.
--
-- Rollback: supabase/rollbacks/rollback_no_referral_loops_v67.sql
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.guard_member_referrer()
returns trigger
language plpgsql
-- Definer: the walk must see the whole chain, whoever is saving.
security definer
set search_path = public
as $$
declare
  v_at    bigint := new.referrer_id;
  v_steps integer := 0;
begin
  if new.referrer_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.referrer_id is not distinct from old.referrer_id then
    return new;
  end if;
  if new.referrer_id = new.id then
    raise exception 'A member cannot be their own referrer'
      using errcode = 'check_violation';
  end if;

  -- Walk up from the chosen referrer. Reaching this member means the
  -- referrer is in their downline. The step limit only guards against an
  -- old loop elsewhere in the chain; real chains are a few levels deep.
  while v_at is not null and v_steps < 100 loop
    select referrer_id into v_at from public.members where id = v_at;
    v_steps := v_steps + 1;
    if v_at = new.id then
      raise exception 'This referrer is already in the member''s downline, so it would make a referral loop'
        using errcode = 'check_violation';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists members_guard_referrer on public.members;
create trigger members_guard_referrer
  before insert or update of referrer_id on public.members
  for each row execute function public.guard_member_referrer();

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (67, 'no_referral_loops')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. The trigger exists (expect 1 row):
--      select tgname from pg_trigger where tgname = 'members_guard_referrer';
-- 2. On STAGING only, inside a transaction that is rolled back, with A
--    the referrer of B (pick two real ids):
--      begin;
--      update public.members set referrer_id = <B> where id = <A>;
--      -- expect: ERROR This referrer is already in the member's downline …
--      rollback;
-- 3. In the app: Edit Member on A. B no longer appears under Referred by.

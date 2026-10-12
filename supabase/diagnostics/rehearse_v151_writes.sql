-- ═══════════════════════════════════════════════════════════════════
-- Rehearsal: what the installed v1.5.1 app writes, after the delivery
-- migrations — and then UNDONE
--
-- For production, where the live app can't be used for testing
-- (2026-10-12). It acts as the real accounts, under their own RLS, the
-- way v1.5.1 does (lib/data/supabase_repository.dart at tag v1.5.1):
--   1. the cashier records a till sale: a `sales` row, then the product's
--      new stock on `items` (addSale + updateItem);
--   2. a member asks to withdraw ₱1 (submitWithdrawalRequest), and then
--      more than they have, which v56 must refuse;
--   3. the admin approves one of the pending withdrawals (as 1.5.1's
--      approve does);
--   4. the cashier and the member read what their screens read.
--
-- NOTHING IS KEPT. The block ends by raising an error on purpose, which
-- rolls back every write above it: the sale, the stock change, the
-- withdrawal request and the approval. The error message IS the result:
-- copy it. "REHEARSAL OK" means every step behaved; "REHEARSAL PROBLEM"
-- names the step that did not.
--
-- Run the whole file at once in the SQL editor.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  v_cashier   uuid;
  v_admin     uuid;
  v_member    bigint;
  v_member_pr uuid;
  v_item      bigint;
  v_item_name text;
  v_stock     integer;
  v_left      integer;
  v_pending   uuid;
  v_sale      bigint;
  v_rows      integer;
  v_count     integer;
  v_earn      jsonb;
  v_log       text := '';
  v_problem   text := '';
begin
  -- ── Who and what, chosen as the database owner ───────────────────
  select id into v_cashier from public.profiles where role = 'cashier' order by id limit 1;
  select id into v_admin   from public.profiles where role = 'admin'   order by id limit 1;
  select id, name, stock into v_item, v_item_name, v_stock
    from public.items where stock >= 1 order by id limit 1;
  -- A member with a login and at least ₱1 of Balance still requestable.
  select m.id, pr.id,
         public._member_bucket_earned(m.id, 'balance')
           - coalesce((select sum(w.requested_amount) from public.withdrawal_requests w
                        where w.member_id = m.id and w.source_bucket = 'balance'
                          and w.status in ('approved', 'pending')), 0)
    into v_member, v_member_pr, v_left
    from public.members m
    join public.profiles pr on pr.member_id = m.id
   where not m.is_deleted
     and public._member_bucket_earned(m.id, 'balance')
           - coalesce((select sum(w.requested_amount) from public.withdrawal_requests w
                        where w.member_id = m.id and w.source_bucket = 'balance'
                          and w.status in ('approved', 'pending')), 0) >= 1
   order by m.id limit 1;
  select id into v_pending from public.withdrawal_requests where status = 'pending' order by created_at limit 1;

  v_log := format('cashier=%s admin=%s item=%s (%s, stock %s) member=%s (₱%s requestable) pending=%s',
                  v_cashier is not null, v_admin is not null, v_item, v_item_name, v_stock,
                  v_member, v_left, v_pending is not null);

  -- ── 1. The cashier's till sale ───────────────────────────────────
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_cashier, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  begin
    insert into public.sales (user_id, item_id, item_name, quantity, price, timestamp)
    values (v_cashier, v_item, v_item_name, 1, 1, now())
    returning id into v_sale;
    update public.items
       set stock = stock - 1, last_updated = now(),
           status = public._item_status(stock - 1, category)
     where id = v_item;
    get diagnostics v_rows = row_count;
    if v_rows = 1 then
      v_log := v_log || ' | 1 sale: recorded, stock updated';
    else
      v_problem := v_problem || ' | 1 sale: the stock update changed ' || v_rows || ' rows';
    end if;
    select count(*) into v_count from public.items_with_status;
    v_log := v_log || format(', cashier sees %s products', v_count);
  exception when others then
    v_problem := v_problem || ' | 1 sale FAILED: ' || sqlerrm;
  end;
  execute 'reset role';

  -- ── 2. The member asks to withdraw ───────────────────────────────
  if v_member is null then
    v_log := v_log || ' | 2 withdrawal: skipped (no member with Balance left)';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_member_pr, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      insert into public.withdrawal_requests (member_id, source_bucket, requested_amount, status, created_at)
      values (v_member, 'balance', 1, 'pending', now());
      v_log := v_log || ' | 2 withdrawal ₱1: accepted';
    exception when others then
      v_problem := v_problem || ' | 2 withdrawal ₱1 REFUSED: ' || sqlerrm;
    end;
    begin
      insert into public.withdrawal_requests (member_id, source_bucket, requested_amount, status, created_at)
      values (v_member, 'balance', v_left + 1, 'pending', now());
      v_problem := v_problem || ' | 2 overdraw: was NOT refused';
    exception when others then
      v_log := v_log || ' | 2 overdraw: refused as it should be (' || sqlerrm || ')';
    end;
    begin
      v_earn := public.get_member_earnings(v_member);
      v_log := v_log || ' | 4 member earnings: read (balance ' || (v_earn ->> 'balance') || ')';
    exception when others then
      v_problem := v_problem || ' | 4 member earnings FAILED: ' || sqlerrm;
    end;
    execute 'reset role';
  end if;

  -- ── 3. The admin approves a pending withdrawal ───────────────────
  if v_pending is null then
    v_log := v_log || ' | 3 approve: skipped (none pending)';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      update public.withdrawal_requests
         set status = 'approved', reviewed_by = v_admin, reviewed_at = now()
       where id = v_pending;
      get diagnostics v_rows = row_count;
      if v_rows = 1 then
        v_log := v_log || ' | 3 approve: accepted';
      else
        v_problem := v_problem || ' | 3 approve changed ' || v_rows || ' rows';
      end if;
    exception when others then
      v_problem := v_problem || ' | 3 approve FAILED: ' || sqlerrm;
    end;
    execute 'reset role';
  end if;

  -- ── Undo everything ──────────────────────────────────────────────
  if v_problem = '' then
    raise exception 'REHEARSAL OK (all undone): %', v_log;
  else
    raise exception 'REHEARSAL PROBLEM (all undone):% || log: %', v_problem, v_log;
  end if;
end;
$$;

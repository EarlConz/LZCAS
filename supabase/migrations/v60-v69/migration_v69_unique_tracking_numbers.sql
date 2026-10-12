-- ═══════════════════════════════════════════════════════════════════
-- Migration v69 — A tracking number belongs to one order
--
-- Requires v61 (orders.tracking_number). Safe to re-run.
--
-- Part 3 (2026-10-03): "verify if the tracking number could be duplicated
-- or used for other deliveries again". It could: cashier_mark_shipped
-- (v61) only checked that one was entered. A typo or a copy-paste could
-- put one parcel's number on two orders, and the member of the second
-- would follow someone else's parcel.
--
-- A trigger on orders now refuses a tracking number that another order
-- already has. Numbers are compared ignoring case, spaces and dashes,
-- since couriers print them grouped ("1234 5678 9012") and cashiers type
-- them every which way. It runs only when the number changes, so orders
-- that already share one (if any) are left as they are; section 1 below
-- lists them.
--
-- Not a unique index on purpose: creating one would fail outright on a
-- database that already has a duplicate.
--
-- Rollback: supabase/rollbacks/rollback_unique_tracking_numbers_v69.sql
-- ═══════════════════════════════════════════════════════════════════

-- "1234-5678 abc" and "12345678ABC" are the same parcel.
create or replace function public._tracking_key(p text)
returns text
language sql
immutable
as $$
  select nullif(upper(regexp_replace(coalesce(p, ''), '[\s-]+', '', 'g')), '');
$$;

-- The lookup below, without reading every order.
create index if not exists idx_orders_tracking_key
  on public.orders (public._tracking_key(tracking_number))
  where tracking_number is not null;

create or replace function public.guard_order_tracking_number()
returns trigger
language plpgsql
-- Definer: a cashier must be refused even for an order they can't see.
security definer
set search_path = public
as $$
declare
  v_key   text := public._tracking_key(new.tracking_number);
  v_other uuid;
begin
  if v_key is null then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and v_key is not distinct from public._tracking_key(old.tracking_number) then
    return new;
  end if;

  select o.id into v_other
    from public.orders o
   where public._tracking_key(o.tracking_number) = v_key
     and o.id <> new.id
   limit 1;

  if v_other is not null then
    raise exception 'Tracking number % is already on order %. Check the number on the courier''s receipt.',
      btrim(new.tracking_number), upper(left(v_other::text, 8))
      using errcode = 'unique_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_guard_tracking_number on public.orders;
create trigger orders_guard_tracking_number
  before insert or update of tracking_number on public.orders
  for each row execute function public.guard_order_tracking_number();

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (69, 'unique_tracking_numbers')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

notify pgrst, 'reload schema';

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. Orders that already share a number (expect none):
--      select public._tracking_key(tracking_number) as tracking,
--             array_agg(id) as orders
--        from public.orders
--       where tracking_number is not null
--       group by 1 having count(*) > 1;
-- 2. In the app: ship a courier order with a number already used on
--    another order. Expect "Tracking number … is already on order …".

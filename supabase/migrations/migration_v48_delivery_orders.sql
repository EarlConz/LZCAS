-- ═══════════════════════════════════════════════════════════════════
-- Migration v48 — Member Ordering & Delivery Negotiation
--
-- Adds a member-facing marketplace order workflow with variable item
-- pricing and a negotiable delivery fee:
--
--   orders       — one row per member order + its delivery destination.
--   order_items  — the requested lines; unit_price / subtotal are NULL
--                  until a Cashier (or Admin) prices them.
--
-- Pricing rules:
--   * Product unit prices are NON-negotiable — they are fixed once a
--     Cashier sets them ("Send Quote").
--   * The delivery fee is the ONLY negotiable component. The Member may
--     Agree or Counter; the Cashier may Accept or Repropose.
--
-- Status machine:
--   'Order Placed'                 → member just submitted (no prices yet)
--   'Cashier Pricing & Negotiating'→ cashier sent the item+delivery quote
--   'Member Negotiating'           → member countered the delivery fee
--   'Agreed'                       → both sides agreed; final_total locked
--   'Completed'                    → order recorded in the POS + receipt printed
--   'Cancelled'                    → either side cancelled
--
-- RLS: disabled on these two tables to match the other core business
-- tables (items, sales, members). Role scoping (Cashier/Admin only —
-- Branch Cashiers excluded) is enforced in the app UI, as it is for the
-- rest of the POS.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_delivery_orders_v48.sql
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  member_id bigint not null,
  cashier_id uuid,
  delivery_address text,
  delivery_latitude double precision,
  delivery_longitude double precision,
  status text not null default 'Order Placed'
    check (status in (
      'Order Placed',
      'Cashier Pricing & Negotiating',
      'Member Negotiating',
      'Agreed',
      'Completed',
      'Cancelled'
    )),
  items_total numeric,   -- NULL until the Cashier prices the items
  delivery_fee numeric,  -- NULL until set; the only negotiable component
  final_total numeric,   -- NULL until the order is Agreed
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id bigint not null,
  quantity integer not null default 1,
  unit_price numeric,  -- NULL until the Cashier sets it
  subtotal numeric     -- NULL until the Cashier sets it
);

-- ── Indexes ──────────────────────────────────────────────────────────
create index if not exists idx_orders_member_id
  on public.orders (member_id);
create index if not exists idx_orders_status
  on public.orders (status, created_at desc);
create index if not exists idx_order_items_order_id
  on public.order_items (order_id);
create index if not exists idx_order_items_product_id
  on public.order_items (product_id);

-- ── RLS: disabled (matches items/sales/members) ─────────────────────
alter table public.orders disable row level security;
alter table public.order_items disable row level security;

-- ── Supabase Realtime for `orders` ───────────────────────────────────
-- New tables are not auto-added to the supabase_realtime publication, so
-- the app's toast/chime + live list refresh would silently never fire.
-- Guarded for both "already a member" and "no publication" (plain PG).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      alter publication supabase_realtime add table public.orders;
    exception when duplicate_object then
      null;
    end;
  end if;
end $$;

-- ── Keep `updated_at` current on every order write ──────────────────
create or replace function public.touch_orders_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists orders_touch_updated_at on public.orders;
create trigger orders_touch_updated_at
  before update on public.orders
  for each row execute function public.touch_orders_updated_at();

-- ═══════════════════════════════════════════════════════════════════
-- RPCs — SECURITY DEFINER, set search_path = public, like the rest of
-- the codebase. Centralizing the status machine here prevents the app
-- from ever writing an invalid transition.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Member checkout: atomically insert the order + its lines.
--    `p_items` is a jsonb array: [{"product_id": 1, "quantity": 2}, ...]
create or replace function public.create_delivery_order(
  p_member_id bigint,
  p_delivery_address text,
  p_delivery_latitude double precision,
  p_delivery_longitude double precision,
  p_items jsonb
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id   uuid;
  v_line       jsonb;
  v_product_id bigint;
  v_quantity   integer;
begin
  insert into public.orders (
    member_id,
    delivery_address,
    delivery_latitude,
    delivery_longitude,
    status
  ) values (
    p_member_id,
    p_delivery_address,
    p_delivery_latitude,
    p_delivery_longitude,
    'Order Placed'
  )
  returning id into v_order_id;

  for v_line in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_product_id := (v_line->>'product_id')::bigint;
    v_quantity   := coalesce((v_line->>'quantity')::integer, 1);
    if v_quantity > 0 then
      insert into public.order_items (order_id, product_id, quantity)
      values (v_order_id, v_product_id, v_quantity);
    end if;
  end loop;

  return v_order_id;
end;
$$;

-- 2. Cashier "Send Quote": fix every item price (non-negotiable from here)
--    and propose an initial delivery fee.
--    `p_lines` is a jsonb array:
--      [{"product_id": 1, "unit_price": 50.00, "subtotal": 100.00}, ...]
create or replace function public.cashier_send_quote(
  p_order_id     uuid,
  p_cashier_id   uuid,
  p_items_total  numeric,
  p_delivery_fee numeric,
  p_lines        jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line jsonb;
begin
  update public.orders
     set cashier_id   = p_cashier_id,
         items_total  = p_items_total,
         delivery_fee = p_delivery_fee,
         status       = 'Cashier Pricing & Negotiating'
   where id = p_order_id;

  for v_line in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb))
  loop
    update public.order_items
       set unit_price = (v_line->>'unit_price')::numeric,
           subtotal   = (v_line->>'subtotal')::numeric
     where order_id = p_order_id
       and product_id = (v_line->>'product_id')::bigint;
  end loop;
end;
$$;

-- 3. Member response to a cashier quote:
--      p_action = 'agree'   → lock final_total, status 'Agreed'
--      p_action = 'counter' → replace the proposed delivery fee with the
--                             member's counter, status 'Member Negotiating'
create or replace function public.member_respond_delivery_order(
  p_order_id    uuid,
  p_action      text,
  p_counter_fee numeric
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_action = 'agree' then
    update public.orders
       set status      = 'Agreed',
           final_total = coalesce(items_total, 0) + coalesce(delivery_fee, 0)
     where id = p_order_id;
  elsif p_action = 'counter' then
    update public.orders
       set delivery_fee = p_counter_fee,
           status       = 'Member Negotiating'
     where id = p_order_id;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end;
$$;

-- 4. Cashier response to a member counter-offer:
--      p_action = 'accept'     → lock final_total, status 'Agreed'
--      p_action = 'repropose'  → propose a new delivery fee, back to
--                                'Cashier Pricing & Negotiating'
create or replace function public.cashier_resolve_delivery_order(
  p_order_id uuid,
  p_action   text,
  p_new_fee  numeric
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_action = 'accept' then
    update public.orders
       set status      = 'Agreed',
           final_total = coalesce(items_total, 0) + coalesce(delivery_fee, 0)
     where id = p_order_id;
  elsif p_action = 'repropose' then
    update public.orders
       set delivery_fee = p_new_fee,
           status       = 'Cashier Pricing & Negotiating'
     where id = p_order_id;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end;
$$;

-- 5. Mark the order completed after the POS sale is recorded + receipt
--    printed. Kept separate so the receipt step is never skipped.
create or replace function public.complete_delivery_order(
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
     set status = 'Completed'
   where id = p_order_id;
end;
$$;

-- 6. Cancel an order from either side before it is Agreed.
create or replace function public.cancel_delivery_order(
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
     set status = 'Cancelled'
   where id = p_order_id;
end;
$$;

-- ── Grants (matches migration_v38's RPC pattern) ───────────────────
revoke all on function public.create_delivery_order(bigint, text, double precision, double precision, jsonb) from public;
revoke all on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb) from public;
revoke all on function public.member_respond_delivery_order(uuid, text, numeric) from public;
revoke all on function public.cashier_resolve_delivery_order(uuid, text, numeric) from public;
revoke all on function public.complete_delivery_order(uuid) from public;
revoke all on function public.cancel_delivery_order(uuid) from public;

grant execute on function public.create_delivery_order(bigint, text, double precision, double precision, jsonb) to authenticated;
grant execute on function public.cashier_send_quote(uuid, uuid, numeric, numeric, jsonb) to authenticated;
grant execute on function public.member_respond_delivery_order(uuid, text, numeric) to authenticated;
grant execute on function public.cashier_resolve_delivery_order(uuid, text, numeric) to authenticated;
grant execute on function public.complete_delivery_order(uuid) to authenticated;
grant execute on function public.cancel_delivery_order(uuid) to authenticated;

-- Refresh the PostgREST schema cache so the new RPCs resolve immediately.
-- (No-op when PostgREST is not running; harmless on plain PostgreSQL.)
notify pgrst, 'reload schema';

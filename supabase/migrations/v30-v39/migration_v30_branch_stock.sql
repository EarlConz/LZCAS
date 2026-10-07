-- migration_v30_branch_stock.sql
-- ===========================================================================
-- BRANCH STOCK SYSTEM
-- ---------------------------------------------------------------------------
-- Two-tier inventory:
--   * Central stock  = public.items.stock            (admin/inventory manage)
--   * Branch stock   = public.branch_stock (per branch-cashier account)
--
-- Admin / main cashier "gives out" stock: a true TRANSFER that DEDUCTS central
-- stock and ADDS it to a branch cashier's allocation (total is conserved).
-- Branch cashiers sell from — and only see — their own allocation.
--
-- Ownership model: per branch-cashier ACCOUNT (owner_id = profiles.id / uid).
--
-- Verbs (all audited in public.stock_transfers):
--   give_out : central -> branch   (transfer_stock_to_branch)
--   return   : branch  -> central   (return_branch_stock)
--   adjust   : correct a branch count in place, central untouched (adjust_branch_stock)
--   sale     : branch  -> customer  (record_branch_sale; decrements branch_stock,
--                                     writes a normal public.sales row)
--
-- Authorization:
--   give_out/return/adjust -> admin or cashier  (can_manage_branch_stock)
--   record_branch_sale     -> the branch cashier themself (auth.uid())
--
-- Idempotent & additive. Reverse with rollbacks/rollback_branch_stock_v30.sql.
-- ===========================================================================

-- ── Tables ─────────────────────────────────────────────────────────────────

create table if not exists public.branch_stock (
  owner_id   uuid    not null,               -- branch cashier's profiles.id / auth uid
  item_id    bigint  not null,
  quantity   integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (owner_id, item_id)
);
alter table public.branch_stock disable row level security;

create table if not exists public.stock_transfers (
  id            bigint generated always as identity primary key,
  item_id       bigint  not null,
  item_name     text    not null,            -- snapshot: survives item rename/delete
  to_owner_id   uuid    not null,            -- branch cashier involved
  quantity      integer not null,            -- +give_out / -return / signed delta for adjust
  transfer_type text    not null default 'give_out'
                  check (transfer_type in ('give_out','return','adjust')),
  created_by    uuid    not null,            -- staff who performed it
  note          text,
  created_at    timestamptz not null default now()
);
alter table public.stock_transfers disable row level security;

create index if not exists idx_branch_stock_owner       on public.branch_stock (owner_id);
create index if not exists idx_stock_transfers_owner     on public.stock_transfers (to_owner_id);
create index if not exists idx_stock_transfers_created   on public.stock_transfers (created_at desc);

-- ── View: branch on-hand, shaped like `items` so the app maps it via Item ───
-- Exposes owner_id for filtering; computes Good/Low/Out from the item's
-- category threshold (same rule as items_with_status).
create or replace view public.branch_stock_view
with (security_invoker = true) as
select
  bs.owner_id,
  i.id          as id,
  i.name        as name,
  i.category    as category,
  bs.quantity   as stock,
  bs.updated_at as last_updated,
  case
    when bs.quantity <= 0 then 'Out of Stock'
    when bs.quantity < coalesce(c.low_stock_threshold, 50) then 'Low Stock'
    else 'Good'
  end as status
from public.branch_stock bs
join public.items i on i.id = bs.item_id
left join public.categories c on c.name = i.category;

grant select on public.branch_stock_view to authenticated, anon;

-- ── Authorization helper: who may move branch stock (admin / main cashier) ──
create or replace function public.can_manage_branch_stock()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin','cashier')
  );
$$;

-- ── give_out: central -> branch ─────────────────────────────────────────────
create or replace function public.transfer_stock_to_branch(
  p_item_id  bigint,
  p_owner_id uuid,
  p_quantity integer,
  p_note     text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_central integer;
  v_name    text;
begin
  if not public.can_manage_branch_stock() then
    raise exception 'Not authorized to transfer stock';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be a positive number';
  end if;
  if not exists (select 1 from public.profiles where id = p_owner_id and role = 'branch_cashier') then
    raise exception 'Recipient is not a branch cashier';
  end if;

  select stock, name into v_central, v_name
  from public.items where id = p_item_id for update;
  if v_central is null then
    raise exception 'Item % not found', p_item_id;
  end if;
  if v_central < p_quantity then
    raise exception 'Not enough central stock for % (have %, need %)', v_name, v_central, p_quantity;
  end if;

  update public.items
    set stock = stock - p_quantity, last_updated = now()
    where id = p_item_id;

  insert into public.branch_stock (owner_id, item_id, quantity, updated_at)
  values (p_owner_id, p_item_id, p_quantity, now())
  on conflict (owner_id, item_id)
    do update set quantity = public.branch_stock.quantity + excluded.quantity,
                  updated_at = now();

  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, v_name, p_owner_id, p_quantity, 'give_out', auth.uid(), p_note);
end;
$$;

-- ── return: branch -> central ───────────────────────────────────────────────
create or replace function public.return_branch_stock(
  p_item_id  bigint,
  p_owner_id uuid,
  p_quantity integer,
  p_note     text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_branch integer;
  v_name   text;
begin
  if not public.can_manage_branch_stock() then
    raise exception 'Not authorized to return stock';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be a positive number';
  end if;

  select quantity into v_branch
  from public.branch_stock where owner_id = p_owner_id and item_id = p_item_id for update;
  select name into v_name from public.items where id = p_item_id;
  if coalesce(v_branch, 0) < p_quantity then
    raise exception 'Not enough branch stock to return for % (have %, need %)',
      coalesce(v_name, 'item'), coalesce(v_branch, 0), p_quantity;
  end if;

  update public.branch_stock
    set quantity = quantity - p_quantity, updated_at = now()
    where owner_id = p_owner_id and item_id = p_item_id;

  update public.items
    set stock = stock + p_quantity, last_updated = now()
    where id = p_item_id;

  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, coalesce(v_name, ''), p_owner_id, -p_quantity, 'return', auth.uid(), p_note);
end;
$$;

-- ── adjust: set a branch count in place (spoilage/miscount); central untouched ─
create or replace function public.adjust_branch_stock(
  p_item_id      bigint,
  p_owner_id     uuid,
  p_new_quantity integer,
  p_note         text default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_old  integer;
  v_name text;
begin
  if not public.can_manage_branch_stock() then
    raise exception 'Not authorized to adjust stock';
  end if;
  if p_new_quantity is null or p_new_quantity < 0 then
    raise exception 'New quantity must be zero or greater';
  end if;

  select quantity into v_old
  from public.branch_stock where owner_id = p_owner_id and item_id = p_item_id for update;
  v_old := coalesce(v_old, 0);
  select name into v_name from public.items where id = p_item_id;

  insert into public.branch_stock (owner_id, item_id, quantity, updated_at)
  values (p_owner_id, p_item_id, p_new_quantity, now())
  on conflict (owner_id, item_id)
    do update set quantity = excluded.quantity, updated_at = now();

  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, coalesce(v_name, ''), p_owner_id, p_new_quantity - v_old, 'adjust', auth.uid(), p_note);
end;
$$;

-- ── sale: branch cashier sells from their own allocation ────────────────────
-- Decrements branch_stock and writes a normal sales row (user_id = the cashier),
-- so existing sales reporting keeps working unchanged. Blocks overselling.
create or replace function public.record_branch_sale(
  p_item_id   bigint,
  p_quantity  integer,
  p_price     integer default 0,
  p_buyer_id  bigint  default null,
  p_buyer_name text   default null,
  p_timestamp timestamptz default null
) returns bigint language plpgsql security definer set search_path = public as $$
declare
  v_qty     integer;
  v_name    text;
  v_sale_id bigint;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and role = 'branch_cashier') then
    raise exception 'Only a branch cashier can record a branch sale';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Quantity must be a positive number';
  end if;

  select quantity into v_qty
  from public.branch_stock where owner_id = auth.uid() and item_id = p_item_id for update;
  select name into v_name from public.items where id = p_item_id;
  if coalesce(v_qty, 0) < p_quantity then
    raise exception 'Not enough branch stock for % (have %, need %)',
      coalesce(v_name, 'item'), coalesce(v_qty, 0), p_quantity;
  end if;

  update public.branch_stock
    set quantity = quantity - p_quantity, updated_at = now()
    where owner_id = auth.uid() and item_id = p_item_id;

  insert into public.sales (user_id, item_id, item_name, quantity, price, buyer_id, buyer_name, timestamp)
  values (auth.uid(), p_item_id, coalesce(v_name, ''), p_quantity, p_price, p_buyer_id, p_buyer_name,
          coalesce(p_timestamp, now()))
  returning id into v_sale_id;

  return v_sale_id;
end;
$$;

grant execute on function public.can_manage_branch_stock()                              to authenticated;
grant execute on function public.transfer_stock_to_branch(bigint, uuid, integer, text)  to authenticated;
grant execute on function public.return_branch_stock(bigint, uuid, integer, text)       to authenticated;
grant execute on function public.adjust_branch_stock(bigint, uuid, integer, text)       to authenticated;
grant execute on function public.record_branch_sale(bigint, integer, integer, bigint, text, timestamptz) to authenticated;

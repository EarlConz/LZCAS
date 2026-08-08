-- rollback_branch_transfer_reports_v31.sql
-- Reverts migration_v31: restores the v30 give-out / return functions that do
-- NOT write stock_movements rows. Branch transfers stop appearing in Reports
-- (they remain under Branch Stock -> Transfers).
-- Optional cleanup of the movement rows this feature created is at the bottom.

create or replace function public.transfer_stock_to_branch(
  p_item_id bigint, p_owner_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_central integer; v_name text;
begin
  if not public.can_manage_branch_stock() then raise exception 'Not authorized to transfer stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be a positive number'; end if;
  if not exists (select 1 from public.profiles where id = p_owner_id and role = 'branch_cashier') then
    raise exception 'Recipient is not a branch cashier';
  end if;
  select stock, name into v_central, v_name from public.items where id = p_item_id for update;
  if v_central is null then raise exception 'Item % not found', p_item_id; end if;
  if v_central < p_quantity then
    raise exception 'Not enough central stock for % (have %, need %)', v_name, v_central, p_quantity;
  end if;
  update public.items set stock = stock - p_quantity, last_updated = now() where id = p_item_id;
  insert into public.branch_stock (owner_id, item_id, quantity, updated_at)
  values (p_owner_id, p_item_id, p_quantity, now())
  on conflict (owner_id, item_id)
    do update set quantity = public.branch_stock.quantity + excluded.quantity, updated_at = now();
  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, v_name, p_owner_id, p_quantity, 'give_out', auth.uid(), p_note);
end; $$;

create or replace function public.return_branch_stock(
  p_item_id bigint, p_owner_id uuid, p_quantity integer, p_note text default null
) returns void language plpgsql security definer set search_path = public as $$
declare v_branch integer; v_name text;
begin
  if not public.can_manage_branch_stock() then raise exception 'Not authorized to return stock'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be a positive number'; end if;
  select quantity into v_branch from public.branch_stock where owner_id = p_owner_id and item_id = p_item_id for update;
  select name into v_name from public.items where id = p_item_id;
  if coalesce(v_branch, 0) < p_quantity then
    raise exception 'Not enough branch stock to return for % (have %, need %)', coalesce(v_name,'item'), coalesce(v_branch,0), p_quantity;
  end if;
  update public.branch_stock set quantity = quantity - p_quantity, updated_at = now() where owner_id = p_owner_id and item_id = p_item_id;
  update public.items set stock = stock + p_quantity, last_updated = now() where id = p_item_id;
  insert into public.stock_transfers (item_id, item_name, to_owner_id, quantity, transfer_type, created_by, note)
  values (p_item_id, coalesce(v_name,''), p_owner_id, -p_quantity, 'return', auth.uid(), p_note);
end; $$;

-- Optional: remove the movement rows this feature logged.
-- delete from public.stock_movements where movement_type in ('transfer_out','transfer_in');

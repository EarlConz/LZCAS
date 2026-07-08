-- ═══════════════════════════════════════════════════════════════════
-- Active Category Deletion Prevention — Database Guardrail
-- Safe to re-run. Designed to be sourced after schema.sql.
-- ═══════════════════════════════════════════════════════════════════

-- ── Guardrail: prevent deleting a category still used by items ────

create or replace function public.prevent_active_category_deletion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usage_count integer;
begin
  -- items.category is a text column that stores the category *name*;
  -- match it case-insensitively against the category being deleted.
  select count(*)
    into v_usage_count
  from public.items
  where lower(trim(category)) = lower(trim(old.name));

  if v_usage_count > 0 then
    raise exception
      using errcode  = 'P0001',
            message  = 'Cannot delete this category because it is '
                       'currently assigned to active inventory items.';
  end if;

  return old;
end;
$$;

-- Attach trigger (idempotent)
drop trigger if exists trg_prevent_category_delete on public.categories;
create trigger trg_prevent_category_delete
  before delete on public.categories
  for each row
  execute function public.prevent_active_category_deletion();

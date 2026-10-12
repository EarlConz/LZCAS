-- ═══════════════════════════════════════════════════════════════════
-- Rollback v73 — takes back out of realtime only the tables v73 added
-- (its ledger note, "added: announcements,branch_stock"). Tables that were
-- already published before v73 stay published. The app keeps working:
-- those two screens just stop updating from other devices.
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  v_note text;
  t      text;
begin
  select note into v_note from public.schema_migrations where version = 73;
  if v_note is null or v_note not like 'added: %' or length(v_note) <= 7 then
    raise notice 'No record of what v73 added; nothing removed.';
    return;
  end if;
  foreach t in array string_to_array(nullif(substr(v_note, 8), ''), ',')
  loop
    begin
      execute format('alter publication supabase_realtime drop table public.%I', t);
    exception when undefined_object then
      null;
    end;
  end loop;
end $$;

delete from public.schema_migrations where version = 73;

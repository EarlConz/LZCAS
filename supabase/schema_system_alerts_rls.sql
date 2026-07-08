-- ═══════════════════════════════════════════════════════════════════
-- System Alerts RLS Policies
-- Safe to re-run. Enables RLS with proper policies instead of
-- disabling it — authenticated users can read, insert, and update.
-- ═══════════════════════════════════════════════════════════════════

-- Enable RLS (replaces the old "disable row level security" approach)
alter table public.system_alerts enable row level security;

-- Anyone logged in can read alerts (dashboard, notification badge)
drop policy if exists "system_alerts_read_authenticated" on public.system_alerts;
create policy "system_alerts_read_authenticated" on public.system_alerts
  for select to authenticated
  using (true);

-- Anyone logged in can insert alerts (ping warnings, manual creation)
drop policy if exists "system_alerts_insert_authenticated" on public.system_alerts;
create policy "system_alerts_insert_authenticated" on public.system_alerts
  for insert to authenticated
  with check (true);

-- Anyone logged in can update alerts (snooze, dismiss, mark read)
drop policy if exists "system_alerts_update_authenticated" on public.system_alerts;
create policy "system_alerts_update_authenticated" on public.system_alerts
  for update to authenticated
  using (true)
  with check (true);

-- Only admins can delete alerts
drop policy if exists "system_alerts_delete_admin" on public.system_alerts;
create policy "system_alerts_delete_admin" on public.system_alerts
  for delete to authenticated
  using (public.is_admin());

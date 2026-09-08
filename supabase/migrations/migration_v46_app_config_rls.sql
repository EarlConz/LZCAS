-- ═══════════════════════════════════════════════════════════════════
-- Migration v46 — Declare app_config's RLS instead of assuming it
--
-- ── What went wrong ────────────────────────────────────────────────
-- schema.sql ends with `alter table public.app_config disable row level
-- security`, and no migration ever turned it back on. Staging nonetheless
-- had RLS ENABLED with no policies, so:
--
--   • every write failed — "new row violates row-level security policy
--     for table app_config" (42501), which is how this was found;
--   • every read returned nothing. That one was silent. `fetchAppConfig`
--     catches its own exception and returns {}, and every ConfigService
--     getter falls back to a hardcoded default, so the app kept running
--     on built-in values — currency symbol, notifications, all three
--     birthday settings, category low-stock thresholds — with nothing on
--     screen to say the database was not being read.
--
-- Almost certainly the dashboard's one-click "Enable RLS" on a table it
-- flagged as unprotected. The lesson is not "do not click it" — the table
-- genuinely should have RLS. The lesson is that a table whose protection
-- is left implicit will eventually be changed by someone, and nothing
-- here recorded what it was supposed to be.
--
-- ── What this does ─────────────────────────────────────────────────
-- Turns RLS on deliberately and writes the policies down, so the intent
-- lives in version control rather than in a checkbox.
--
--   read   — anyone, signed in or not.
--   write  — admins only, matching every other settings surface.
--   delete — nobody. The keys are fixed; the app upserts values.
--
-- ── Why reads are open to anon ─────────────────────────────────────
-- ConfigService.load() runs at startup, before anyone has signed in.
-- Restricting SELECT to `authenticated` would leave the login screen and
-- every pre-auth path on defaults, then never re-read after login — the
-- exact silent-fallback failure this migration exists to end.
--
-- Nothing in here is a secret. It is the currency symbol, a few feature
-- switches, and the birthday greeting's wording — all of it visible in
-- the UI to anyone who signs in anyway. If a genuinely sensitive setting
-- is ever added, it does not belong in this table.
--
-- Safe to re-run. Rollback: supabase/rollbacks/rollback_app_config_rls_v46.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── Clear out dashboard-era policies FIRST ─────────────────────────
-- Production carries two policies that no migration in this repo created:
--
--   app_config_select_auth  SELECT  using is_authenticated()
--   app_config_write_admin  ALL     using user_has_role(ARRAY['admin'])
--
-- They are inert there — RLS is off — so dropping them changes nothing about
-- current behaviour. They are dropped BEFORE `enable row level security` so
-- there is never an instant where they are live: both reference helper
-- functions (`is_authenticated`, `user_has_role`) that exist on that database
-- and nowhere in version control, and a policy calling a function that is not
-- there fails every query against the table.
--
-- The `ALL` one also grants DELETE, which the policy set below deliberately
-- withholds — see the note under the UPDATE policy.
--
-- If you want that role model back, write it as a migration. The point of
-- this file is that app_config's protection is declared in one place.
drop policy if exists "app_config_select_auth"  on public.app_config;
drop policy if exists "app_config_write_admin"  on public.app_config;

drop policy if exists "app_config_select" on public.app_config;
drop policy if exists "app_config_insert" on public.app_config;
drop policy if exists "app_config_update" on public.app_config;

alter table public.app_config enable row level security;

drop policy if exists "app_config_select" on public.app_config;
create policy "app_config_select" on public.app_config
  for select to anon, authenticated
  using (true);

drop policy if exists "app_config_insert" on public.app_config;
create policy "app_config_insert" on public.app_config
  for insert to authenticated
  with check (public.is_admin());

-- Both arms are needed. `updateAppConfig` upserts, and Postgres checks the
-- UPDATE policy's USING against the existing row and its WITH CHECK against
-- the new one when the ON CONFLICT path is taken.
drop policy if exists "app_config_update" on public.app_config;
create policy "app_config_update" on public.app_config
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- No DELETE policy, on purpose. Every key is created by a migration and
-- updated in place; removing one would send the app back to a hardcoded
-- default with no indication anything had changed.

-- ── Restore any key that went missing ──────────────────────────────
-- Writes have been failing, so a key a migration expected to create may
-- never have landed. This puts back only what is absent and never
-- overwrites a value that is already set.
insert into public.app_config (key, value) values
  ('birthday_greetings_enabled', 'true'),
  ('birthday_greeting_days',     '30'),
  ('birthday_greeting_message',
   'Everyone at GUTVita wishes you all the best for the year ahead. Thank you for being part of the team.'),
  ('birthday_greeting_image',    '')
on conflict (key) do nothing;

insert into public.schema_migrations (version, name)
values (46, 'app_config_rls')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- RLS on, and exactly the three policies below — no leftovers:
--   select relrowsecurity from pg_class
--    where oid = 'public.app_config'::regclass;              -- expect true
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'app_config'
--    order by policyname;
--   -- expect exactly: app_config_insert / app_config_select / app_config_update
--   -- anything else means a policy was added outside version control again.
--
-- Every key is present:
--   select key, value from public.app_config order by key;
--
-- The real test is in the app, not here — this editor is superuser and
-- bypasses RLS. Sign in as an admin and save the birthday greeting; sign
-- in as a member and confirm the currency symbol is still right.

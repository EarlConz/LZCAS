-- ═══════════════════════════════════════════════════════════════════
-- Migration v58 — Push notifications for delivery orders
--
-- Requires v57. Pairs with the Edge Function supabase/functions/order-push.
--
-- The in-app alerts (delivery_notification_service.dart) only reach an
-- app that is open. A rider whose phone is in their pocket heard nothing
-- about a new assignment. Push notifications (Firebase Cloud Messaging)
-- reach a phone whose app is closed.
--
-- ── How a push travels ─────────────────────────────────────────────
--   1. The app, after sign-in on Android, registers its FCM token here
--      (register_push_token). One row per phone; a phone that signs in as
--      someone else moves to them.
--   2. An order changes status, or changes rider. A trigger queues one
--      HTTP call to the order-push function through pg_net. The call is
--      queued, not made, inside the transaction: the order update never
--      waits on the network, and never fails because of it.
--   3. order-push reads the order, works out who to tell (the same rules
--      as the in-app alerts), and sends through FCM to their tokens.
--
-- ── Configuration lives in Vault, not here ─────────────────────────
-- The trigger needs the function's URL and a shared secret the function
-- checks. Both differ per environment and the secret must stay out of git,
-- so they are Vault secrets, created once per environment by hand:
--
--   select vault.create_secret('<function url>',  'order_push_url');
--   select vault.create_secret('<shared secret>', 'order_push_secret');
--
-- Until both exist the trigger does nothing, so applying this migration
-- changes no behaviour on its own.
--
-- Safe to re-run. Rollback:
--   supabase/rollbacks/rollback_push_notifications_v58.sql
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Outgoing HTTP from the database ─────────────────────────────
create extension if not exists pg_net with schema extensions;

-- ── 2. Where each phone can be reached ─────────────────────────────
create table if not exists public.push_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text not null default 'android',
  updated_at timestamptz not null default now()
);

create index if not exists idx_push_tokens_user on public.push_tokens (user_id);

-- No policies at all: the app never reads or writes this table directly.
-- It goes through the two functions below, and order-push reads it with
-- the service role. A token is an address someone else could spam.
alter table public.push_tokens enable row level security;

-- Register this phone for the signed-in account. Deletes first so a
-- phone that changes hands (a shared device, a re-login) is only ever
-- one person's.
create or replace function public.register_push_token(
  p_token    text,
  p_platform text default 'android'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'A push token is required';
  end if;
  delete from public.push_tokens where token = p_token;
  insert into public.push_tokens (token, user_id, platform)
  values (p_token, auth.uid(), coalesce(nullif(btrim(p_platform), ''), 'android'));
end;
$$;

-- Sign-out: stop sending this account's alerts to this phone. Only the
-- caller's own token; anyone else's is not theirs to remove.
create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_tokens
   where token = p_token and user_id = auth.uid();
$$;

-- ── 3. The trigger ─────────────────────────────────────────────────
create or replace function public.queue_order_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url    text;
  v_secret text;
begin
  select decrypted_secret into v_url
    from vault.decrypted_secrets where name = 'order_push_url';
  select decrypted_secret into v_secret
    from vault.decrypted_secrets where name = 'order_push_secret';
  if v_url is null or v_secret is null then
    return new;   -- not configured in this environment
  end if;

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || v_secret),
    body    := jsonb_build_object(
                 'order_id',        new.id,
                 'type',            lower(tg_op),
                 'old_status',      case when tg_op = 'UPDATE' then old.status end,
                 'old_delivery_id', case when tg_op = 'UPDATE' then old.delivery_id end,
                 -- Whoever made the change is not told about it.
                 'actor',           auth.uid())
  );
  return new;
exception when others then
  -- A notification is never worth failing an order update for.
  raise warning 'order push not queued for %: %', new.id, sqlerrm;
  return new;
end;
$$;

drop trigger if exists orders_push_insert on public.orders;
create trigger orders_push_insert
  after insert on public.orders
  for each row execute function public.queue_order_push();

-- Status changes, and a rider swap (Assigned → Assigned to someone else,
-- which leaves the status alone but is news to both riders).
drop trigger if exists orders_push_update on public.orders;
create trigger orders_push_update
  after update of status, delivery_id on public.orders
  for each row
  when (old.status is distinct from new.status
        or old.delivery_id is distinct from new.delivery_id)
  execute function public.queue_order_push();

-- ── 4. Grants ──────────────────────────────────────────────────────
revoke all on table public.push_tokens from anon, authenticated;
revoke all on function public.register_push_token(text, text) from public;
revoke all on function public.unregister_push_token(text) from public;
revoke all on function public.queue_order_push() from public;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

-- ── Ledger ─────────────────────────────────────────────────────────
insert into public.schema_migrations (version, name)
values (58, 'push_notifications')
on conflict (version) do update
  set applied_at = now(), applied_by = current_user, verified = true;

-- ── Verify ─────────────────────────────────────────────────────────
-- 1. pg_net is on and the triggers exist (expect 2 rows):
--      select tgname from pg_trigger
--       where tgrelid = 'public.orders'::regclass and tgname like 'orders_push%';
-- 2. After the Vault secrets are set and an order changes status, the
--    call was made (status_code 200 expected):
--      select id, status_code, content::text, created
--        from net._http_response order by created desc limit 5;
-- 3. A phone registered after signing in on the new app:
--      select user_id, platform, updated_at from public.push_tokens;

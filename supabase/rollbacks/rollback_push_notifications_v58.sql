-- ═══════════════════════════════════════════════════════════════════
-- Rollback v58 — Push notifications
--
-- Removes the triggers, the token table and its two functions.
--
-- Read first:
--   • Every registered phone is forgotten. Re-applying v58 starts empty;
--     phones register again the next time the app signs in.
--   • pg_net is left installed: other features may use it, and an idle
--     extension costs nothing.
--   • The two Vault secrets are left in place. Remove them by hand if the
--     feature is going away for good:
--       delete from vault.secrets
--        where name in ('order_push_url', 'order_push_secret');
--   • The app built with v58 calls register_push_token after sign-in.
--     Without it that call fails quietly (logged, not shown): the app
--     works, it just receives no pushes.
-- ═══════════════════════════════════════════════════════════════════

drop trigger if exists orders_push_insert on public.orders;
drop trigger if exists orders_push_update on public.orders;
drop function if exists public.queue_order_push();

drop function if exists public.register_push_token(text, text);
drop function if exists public.unregister_push_token(text);
drop table if exists public.push_tokens;

delete from public.schema_migrations where version = 58;

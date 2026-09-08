# Production rollout — v35 → v46

> ## ✅ Completed 2026-09-09 — production is at v46
>
> All twelve applied, every check passed. `member_transactions` and
> `earnings_history` came through with **zero drift** (452 and 101 rows, no
> changed values). Keep this file: the next rollout starts from v47, and the
> notes below are what the process actually cost.
>
> **What the run turned up, none of it predicted from the repo:**
>
> - **`app_config` had two policies made in the dashboard** —
>   `app_config_select_auth` and `app_config_write_admin` — referencing
>   `is_authenticated()` and `user_has_role(text[])`, helper functions that
>   exist on production and in no source file. They were inert (RLS was off)
>   and would have silently activated the moment v46 enabled it, including an
>   unintended DELETE grant. v46 now drops them by name first. A sweep
>   confirmed the drift was confined to this one table; the two functions are
>   now unused and were deliberately left alone.
> - **v8 never ran on production, correctly.** The ledger left a hole where it
>   should be, which looked alarming — v8 is what makes the `member-ids`
>   bucket private. Production has no storage buckets at all, so there was
>   nothing to secure and no exposure. `profiles.id_image_path` exists
>   regardless, so the ID-photo feature has never worked on prod: worth
>   confirming with the client that nobody expects it to.
> - **The diagnostic crashed on its first real use.** It used
>   `'public.announcements'::regclass`, which raises when the table is absent
>   — exactly the database it was written for. Now `to_regclass`.
> - **v44 created production's first storage bucket**, and its
>   `storage.objects` policies applied without the permissions trouble that
>   was expected.
> - **The v45 re-run at step 13 is easy to skip** and nothing complains if you
>   do — v46 self-records, so the ledger looks plausible while missing v35–v44
>   entirely. Check for gaps, not just for the last row.
>
> **Left deliberately undone:** `backup_member_transactions_20260909` and
> `backup_earnings_history_20260909` are still in the database. Drop them once
> the release has settled.

Prod was at **v34**. Staging was at v46. This is the runbook for
closing that gap.

Tick each box as you go. If you stop partway, the ticks plus
`public.schema_migrations` are the record of where you got to — not memory,
and not a chat log.

---

## ⛔ Never on production

- **`schema/schema.sql`** — drops every member, sale, item and transaction.
  It is for fresh projects only. It is in the same folder as everything else
  here; do not reach for it by habit.
- **`maintenance/reset_tables.sql`**, **`maintenance/deploy_reset.sql`** —
  same reason.
- Any **rollback** script, unless you have decided to undo a specific
  migration and have read that script's header.

Only files from `migrations/` belong in this run.

---

## Before you start

- [ ] **Take a restore point.** PITR and scheduled backups are a paid
      Supabase feature. On the free plan, do the three things below instead —
      together they cover this rollout's actual exposure, which is narrower
      than it looks.

      **Why narrower:** eleven of the twelve migrations are purely additive
      DDL — new tables, columns, functions, policies. None UPDATEs or DELETEs
      an existing row. The three with data logic (v39, v40, v41) act on tables
      v36 creates moments earlier, so on prod they run against empty tables.
      Only v35 goes near financial data, and it is additive too; its real risk
      is that it *drops and recreates* `get_member_earnings_sources`.

      **1. Snapshot the tables v35 touches, inside the database.** Instant,
      free, no credentials to hand around. Use today's date in the names:

      ```sql
      create table backup_member_transactions_20260909 as
        select * from public.member_transactions;
      create table backup_earnings_history_20260909 as
        select * from public.earnings_history;

      -- Confirm the copies match before trusting them
      select (select count(*) from public.member_transactions)          as live_txn,
             (select count(*) from backup_member_transactions_20260909) as copy_txn,
             (select count(*) from public.earnings_history)             as live_hist,
             (select count(*) from backup_earnings_history_20260909)    as copy_hist;
      ```

      Drop these once the rollout is verified — they are a safety net, not a
      permanent second copy of the ledger.

      **2. Save the function v35 replaces**, so you can put the old one back
      exactly as it was:

      ```sql
      select pg_get_functiondef(p.oid)
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'get_member_earnings_sources';
      ```

      Copy the output into a file. This *is* the rollback for v35's riskiest
      part.

      **3. A full dump, if you can.** From the machine, using the connection
      string in Dashboard → Settings → Database. Keep the password to
      yourself — nobody needs it but you:

      ```
      pg_dump "<connection string>" --no-owner --file prod_backup_20260909.sql
      ```

      Note `pg_dump` must be at least the server's major version or it refuses
      to run. If it is not installed, `npx supabase db dump` is the easier
      route.

      If the client's business data warrants it, one month of Pro for the
      rollout window is also a legitimate answer — that is their call, not a
      technical blocker.
- [ ] **Nobody is mid-transaction.** Pick a window with no cashiers posting
      sales. Most of these migrations are instant, but v35 touches earnings.
- [ ] **Confirm where prod actually is.** Run
      `diagnostics/check_applied_migrations.sql`. Do not trust "prod is on
      v34" — verify it. Everything v35 and above should read MISSING.
- [ ] **Check `app_config`'s RLS state**, because it was never declared and
      whatever it is on prod is by accident:

      ```sql
      select relrowsecurity as rls_enabled
      from pg_class where oid = 'public.app_config'::regclass;

      select policyname, cmd from pg_policies
      where schemaname = 'public' and tablename = 'app_config';
      ```

      `true` with **zero policies** means prod has been silently running on
      hardcoded defaults, exactly as staging was. v46 fixes it either way.

- [ ] **Record the earnings baseline.** v35 is the only migration here that
      touches live financial data, so capture what the numbers are *before*
      it runs, for a handful of real members:

      ```sql
      select m.id, m.first_name, m.last_name,
             (select sum(mt.price) from public.member_transactions mt
               where mt.member_id = m.id) as txn_total
      from public.members m
      order by m.id
      limit 20;
      ```

      Save the output. If v35 goes wrong, this is what "wrong" is measured
      against.

---

## The order

Apply one at a time, in this order. After each: read the file's own **Verify**
block at the bottom and run it.

- [ ] **v45** — ledger, applied *first* so prod's starting state is recorded
      before anything changes. It backfills by detection, so on a v34 database
      it records v2–v34 and claims nothing above that.
- [ ] **v35** — admin fund adjustments. ⚠️ **The one to be careful with.**
      Drops and recreates `get_member_earnings_sources` (v34's function) to add
      an OUT column, adds `earnings_history.note`, adds the `fund_adjustments`
      table. Additive — it does not modify a single existing earnings row.
      **Stop here.** Re-run the baseline query above and confirm the totals are
      unchanged. Open the app and check one member's earnings screen.
- [ ] **v36** — announcements, saved items, birthday config keys. New tables;
      touches no existing data.
- [ ] **v37** — `profiles` location columns.
- [ ] **v38** — `member_branch_stock()` RPC.
- [ ] **v39** — announcement audiences. The `'resellers'` → `'members'` rewrite
      is a **no-op on prod**: v36 just created the table, so there are no
      announcements to rewrite. Expect the NOTICE to report zero.
- [ ] **v40** — `announcement_reads`. Its backfill is also trivially empty for
      the same reason.
- [ ] **v41** — re-keys `member_saved_items` to `profile_id`. Aborts if any row
      cannot be mapped; there are no rows, so it cannot.
- [ ] **v42** — `server_now()`.
- [ ] **v43** — narrows the announcements read policy to `is_admin()`.
- [ ] **v44** — poster column, nullable body, private `announcement-media`
      bucket, `birthday_greeting_image` key.
- [ ] **v45 again** — re-run it. It is safe to re-run and detection-based, so
      this records everything applied above. Confirm with:

      ```sql
      select version, name, verified from public.schema_migrations
      order by version;
      ```

- [ ] **v46** — `app_config` RLS. Last, because it is the only one that changes
      how the *existing* app reads settings.

---

## After the SQL, before the app

- [ ] Re-run `diagnostics/check_applied_migrations.sql`. Everything APPLIED.
- [ ] **Sign in to production in the app and check the ordinary screens** —
      members, sales, inventory, one member's earnings. The features you just
      migrated are not in the prod build yet; what you are checking is that
      nothing that already worked has stopped.
- [ ] If `app_config` had RLS on with no policies, settings that were
      previously falling back to defaults will now read their real values.
      **The currency symbol and birthday settings may visibly change.** That is
      a correction, not a regression — but tell whoever is watching before
      they report it as a bug.

## Then the app

- [ ] Build production binaries (production flavor — **not** the staging
      dart-defines).
- [ ] Version bumped. The prod build is 1.3.0; this one carries everything
      from v35 to v46.
- [ ] Ship the DB-first rule in reverse: the DB is already ahead, which is the
      safe direction. Do not ship an app build before its migrations again.

---

## If something fails midway

Stop. Do not continue down the list.

The migrations are individually safe to re-run, so a failure part-way through
one is recoverable by fixing the cause and running it again — but only if you
know which one you were on. That is what the ledger and these ticks are for.

`rollbacks/` has a paired script for each. Read its header before running it:
several are lossy, and two (v40, v41) destroy data that only exists because the
migration created it.

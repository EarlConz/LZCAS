# Production rollout — v35 → v46

Prod is believed to be at **v34**. Staging is at v46. This is the runbook for
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

- [ ] **Take a restore point.** Supabase PITR if the plan has it; otherwise
      confirm today's automatic backup exists and note its timestamp. This is
      the highest-value step on the page and the easiest to skip.
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

# Supabase SQL

All SQL is applied **manually** via the Supabase SQL editor (paste & run) —
nothing here is auto-migrated. Folders group files by purpose.

```
supabase/
├── functions/     Edge Functions (create-user, create-member-user, …)
├── schema/        Baseline objects — run on a fresh project
├── migrations/    Ordered, apply-once changes (v2 … v46)
├── rollbacks/     Undo scripts, paired with a migration
├── diagnostics/   Read-only tools (write nothing)
└── maintenance/   Destructive/reset scripts — use with care
```

## schema/

⚠️ **`schema.sql` is destructive and is for fresh projects only.** It drops
every member, sale, item and transaction; only `profiles` and auth users
survive. Never run it on production.

Run these first on a brand-new project, in this order:

1. `schema.sql` — tables, packages, withdrawal_requests, core objects.
2. `enable_rls_staff.sql` — RLS policies + `is_staff()` helper.
3. `schema_category_delete_guard.sql` — category-delete guard.
4. **Then every migration below, in ascending order.**

Step 4 is not optional. `schema.sql` is a starting point, **not a snapshot of
the current schema** — some migrations were folded into it (branch stock
v30–v33, `member_branch_stock` v38) and most were not. There is no
`announcements` table in it at all. A project built from steps 1–3 alone
starts and then fails on announcements, birthday greetings, saved items and
posters.

(`schema.sql.bak` is an old snapshot, kept for reference only.)

## Which migrations are applied?

`public.schema_migrations` (v45) answers this. `verified = false` marks rows
the v45 backfill *assumed* rather than detected — everything predating the
ledger that leaves no trace in the schema.

```sql
select version, name, verified, applied_at::date
from public.schema_migrations order by version;
```

On a database that predates v45, `diagnostics/check_applied_migrations.sql`
infers the same thing by checking for the objects each migration creates.

## migrations/

Numbered changes applied over time. Each file's header explains what it does
and whether it supersedes an earlier one. Apply in ascending version order on a
fresh DB; on an existing DB only the ones not yet applied.

> The _"applied to staging and prod"_ / _"not yet applied anywhere"_ labels
> below are **historical notes, not current state** — they were accurate when
> written and go stale the moment someone applies something without editing
> this file. `public.schema_migrations` is the authority. Read the labels for
> intent and ordering; read the ledger for what is actually there.

**Earnings / compensation history (the `get_member_earnings` RPC + triggers):**

- v6 — earnings RPC introduced
- v19 — Group Sales frozen at purchase time (triggers)
- v20 — Direct/Indirect Referral frozen; Chairman priced per package-period
- v21 — Chairman: immediate on availment + weekly Friday
- v22 — Chairman: per direct referral, paid that week's Friday
- v23 — Chairman: per direct referral, **immediate**, rate frozen at referral time
- v24 — Chairman becomes a **frozen ledger** (trigger + backfill + RPC sums rows)
- v25 — Direct/Indirect/Chairman become **availment-based**: a referral only
  pays when the referred member avails a package; Direct/Indirect are **min-tier
  capped** (lower of earner's vs referral's package, by `hierarchy_rank`);
  Chairman stays the earner's own rate; package-less members get **catch-up**
  when they later avail. Trigger moves from member-registration to first
  package availment. RPC unchanged.
- v26 — Upgrade Referral Bonus becomes **min-tier capped** too (lower of the
  referrer's package vs the package the downline upgraded to). No current-data
  impact with only two tiers; matters once a 3rd+ tier exists. Redefines
  `process_package_upgrade` + extends `referral_bonus_min_tier` with 'upgrade'.
- v27 — Chairman's Bonus becomes **min-tier capped** too (lower of earner's vs
  referral's first-availed package). Extends the helper with 'chairman',
  redefines the availment trigger's chairman inserts, recomputes the Chairman
  ledger. ⚠️ Changes existing earnings (only downward).

> **Live on prod: v27.** All five bonuses (Direct/Indirect Referral, Group
> Sales, Upgrade, Chairman) are stored `member_transactions` rows the RPC sums —
> none recomputed live, so editing package rates never changes history. Direct/
> Indirect are availment-based + min-tier capped; Chairman is availment-gated at
> the earner's own rate. Referral bonuses crystallize at first availment (with
> catch-up), frozen thereafter.

**Branch Cashier role + Branch Stock (v28–v33)** — _applied to staging and
prod (shipped in v1.3.0). Apply in this exact order:_

- v28 — `is_staff()` accepts the new `branch_cashier` role.
- v29 — `profiles.mobile_enabled` flag (admin-granted mobile login for a branch
  cashier; desktop-only by default). Enforced in-app.
- v30 — Branch stock system: `branch_stock` + `stock_transfers` tables,
  `branch_stock_view`, and RPCs `transfer_stock_to_branch`, `return_branch_stock`,
  `adjust_branch_stock`, `record_branch_sale` (two-tier inventory: central
  `items.stock` + per-branch allocation; give-out deducts central).
- v31 — Give-out/return also log `stock_movements` (`transfer_out`/`transfer_in`)
  so branch transfers show up in Reports as **Branch Out / Branch In**. (adjust is
  not logged — it doesn't change central stock.)
- v32 — Include the give-stock **note** in the Reports movement reason
  (`branch - note`).
- v33 — **RLS + policies** for `branch_stock`/`stock_transfers` (the read fix):
  RLS on, SELECT only; admin/main-cashier see all, a branch cashier sees only
  their own rows. All writes stay locked to the SECURITY DEFINER RPCs.

**Itemised earnings sources (v34)** — _needed on BOTH staging and prod._

- v34 — `get_member_earnings_sources(p_member_id)`: the per-credit list behind
  each earnings bucket ("Chairman's Bonus — from Maria Santos"). Must be a
  SECURITY DEFINER RPC because RLS limits a member to their **own** rows in
  `members`/`sales`, so resolving downline names client-side silently returns
  nothing and every row renders "Source not recorded". Same staff-or-self
  authorization as `get_member_earnings`. Read-only; changes no policies.
  Ship with the app build that adds the breakdown card.

**Admin fund adjustments (v35)** — _not yet applied anywhere._

- v35 — `admin_adjust_member_funds(member, bucket, amount, reason)`: the only
  supported way to correct a member's earned funds. **Append-only** — it
  writes a new signed `member_transactions` row whose `item_name` keeps the
  bucket's prefix (`'Chairman Bonus Adjustment — <reason>'` still matches
  `ilike 'Chairman Bonus%'`), so `get_member_earnings` picks it up unchanged
  and the original credits stay intact. Never `UPDATE`s or `DELETE`s a credit.

  Gated by `is_admin()`, **not** `is_staff()`. Refuses a zero amount, a reason
  under 3 characters, and any deduction that would drive the bucket below zero
  (`get_member_earnings` clamps at 0, so a negative bucket would silently
  swallow later earnings).

  Also in v35: `earnings_history.note` (snapshots had no cause, so a decrease
  was guessed at and mislabelled "Withdrawal"); the `fund_adjustments` audit
  table (admin-SELECT only, no INSERT policy — the RPC is the only way in);
  and `get_member_earnings_sources` gains `is_adjustment`, which **drops and
  recreates** the v34 function because `CREATE OR REPLACE` cannot alter OUT
  columns.

  Additive and safe to apply ahead of the app — a v1.3.0 client ignores the
  extra column. The reverse is not: **apply v35 before releasing the build
  that adds the Adjust Funds dialog.**

**Announcements + birthday greetings (v36)** — _not yet applied anywhere._

- v36 — `announcements`, `member_saved_items`, and three `app_config` keys
  (`birthday_greetings_enabled`, `birthday_greeting_days`,
  `birthday_greeting_message`).

  Two things in the policies are load-bearing and easy to "fix" by mistake:

  **There is no DELETE policy on `announcements`, on purpose.** Members can
  save an announcement, so deleting the row would empty their saved list.
  Taking a notice out of circulation sets `archived_at`. Adding a delete
  policy would quietly break saved items.

  **The SELECT policy deliberately does not filter `ends_at`.** It filters
  `archived_at` and audience only — an expired announcement must stay
  readable or a member could not see one they saved. "Current" vs "saved" is
  decided in the app, not by RLS.

  `member_saved_items` holds both kinds. A birthday greeting has no row
  anywhere (it is computed from `members.birthday` when the member opens the
  app), so it is identified by the **year** it was given.

  No scheduler, no cron, no email: the birthday check is pure client-side
  date arithmetic. Applying v36 without the matching app build is harmless —
  nothing reads the tables.

**Cashier / branch cashier saved location (v37)** — _applied to staging and prod._

- v37 — `profiles` gains `latitude`, `longitude`, `address`,
  `location_updated_at` so cashiers/branch cashiers can save their physical
  location. Read by the member "Nearest Cashiers" map. Distance is computed
  client-side; nothing is stored server-side.

**Member cashier stock discovery (v38)** — _not yet applied anywhere._

- v38 — `member_branch_stock()`: a SECURITY DEFINER, read-only RPC that returns
  each branch cashier's on-hand lines (item name, category, quantity, status) to
  **any authenticated caller**. Needed because `branch_stock` RLS (v33) hides
  every branch from a member, so the member "Nearest Cashiers" screen couldn't
  tell stocked branches from out-of-stock ones. Regular cashiers sell from the
  shared central `items` catalog, which members can already read — no RPC needed
  for them. Exposes no transfer audit data. Rollback:
  `rollback_member_cashier_stock_v38.sql`.

**Announcement audiences, unseen popup, server clock (v39–v43)** — _applied to
staging; not yet applied to prod._ Apply in this exact order; v39 has to widen
the audience CHECK before anything writes the new values.

- v39 — audiences become `('all','branches','members')`. Existing `'resellers'`
  rows widen to `'members'` and so become visible to plain members too; the
  script reports how many it rewrote. Not reversible without knowing which rows
  were originally reseller-only.
- v40 — `announcement_reads`, the table behind "unseen notices pop up on open".
  Keyed on `profile_id`, **not** `members.id`, because a branch cashier has no
  members row and branches are an audience as of v39. Insert-and-select only:
  there is deliberately no UPDATE or DELETE policy, so a seen mark cannot be
  taken back. Backfills every existing (account, announcement) pair as already
  seen, so nobody gets a wall of history on first launch.
- v41 — re-keys `member_saved_items` from `member_id` to `profile_id`, which is
  what lets a branch cashier star an announcement at all. **Aborts** if any
  saved row has no matching profile rather than dropping it.
- v42 — `server_now()`: a `stable`, execute-to-`authenticated` RPC returning
  `now()`. The app was asking the device clock whether an announcement was still
  running while RLS asked the server's; a machine weeks fast showed "Ended" on a
  notice it had just created, and members saw nothing. Harmless without the
  matching build — nothing else calls it.
- v43 — narrows the announcements SELECT bypass from `is_staff()` to
  `is_admin()`. v28 put `branch_cashier` inside `is_staff()`, so once v39 made
  branches an audience the policy's first arm matched every cashier and the
  audience check never ran — a "Members only" notice appeared in branch
  terminals. Only admins manage announcements, so nothing else loses access.

> The audience check cannot be verified from the SQL editor: it runs as
> superuser and bypasses RLS entirely. Log in as an actual branch cashier and an
> actual member.

**Posters on announcements and birthday greetings (v44)** — _not yet applied
anywhere._

- v44 — `announcements.image_path`, `body` becomes nullable behind an
  `announcement_has_content` CHECK (a row must have text, a poster, or both —
  never neither), a **private** `announcement-media` bucket, and the
  `birthday_greeting_image` config key. The title stays required: it labels the
  list row, the unseen popup and the saved list, none of which can fall back on
  a picture.

  The bucket's read policy does **not** re-implement the audience rules. It asks
  whether the caller can see an announcement carrying that path, and that
  subquery runs under the caller's own RLS — so it inherits whatever
  `announcements_select` decides, including any later change to it. A public
  bucket was rejected for the obvious reason: it would hand the poster for a
  Members-only notice to anyone with the link, undoing v43 one layer down.

  Rows store the object **path**, not a URL, because the app displays these
  through signed URLs that expire. Applying v44 without the matching app build
  is harmless — nothing writes `image_path`, and every announcement stays
  text-only.

**Migration ledger (v45)** — _apply everywhere, and apply it last._

- v45 — `schema_migrations`: one row per applied migration. Backfills itself
  by detecting what each earlier migration created, so it records the truth
  on whichever database it is run against rather than a fixed list. Rows it
  could not detect (the earnings chain, which only redefines functions) are
  inserted with `verified = false` and say so — a ledger that invents history
  is worse than none, because it gets believed.

  Read by nothing in the app. From v46 onward, every migration ends by
  recording itself and every rollback ends by deleting its row; the footer to
  copy is at the bottom of the v45 file.

**`app_config` RLS (v46)** — _needed everywhere. Check before assuming._

- v46 — declares RLS on `app_config` and writes the policies down: read by
  anyone, write by admins, no delete. It had been left implicit —
  `schema.sql` disables RLS and no migration re-enabled it — and staging was
  found with RLS **on and no policies at all**, almost certainly the
  dashboard's one-click "Enable RLS".

  Both failure modes matter, and only one of them was visible:

  - Writes failed loudly — `42501 new row violates row-level security policy`
    when saving the birthday greeting.
  - **Reads failed silently.** `fetchAppConfig` catches its own exception and
    returns `{}`, and every `ConfigService` getter falls back to a hardcoded
    default, so the app ran on built-in values — currency symbol,
    notifications, all three birthday settings, category low-stock thresholds
    — with nothing on screen to say the table was not being read. The
    repository now logs when that fallback happens.

  Reads are open to `anon` deliberately: `ConfigService.load()` runs before
  sign-in, and restricting SELECT to `authenticated` would leave every
  pre-auth path on defaults and never re-read afterwards — reintroducing the
  same silent failure. Nothing in the table is secret, and nothing secret
  should be put in it.

  v46 also re-inserts the four `birthday_greeting_*` keys with
  `on conflict do nothing`, since a key a migration meant to create may never
  have landed while writes were failing.

  **Check prod for the same thing** — the RLS state was never declared, so
  whatever it is there, it is by accident.

> **Rollout order (all environments):** DB migrations first (invisible/reversible)
> → app release second (`UserRole.fromString` throws on unknown roles, so the new
> build must ship before any `branch_cashier` account exists) → create accounts
> last. Edge Functions `create-user` / `update-user` must be **deployed** to the
> target project (staging currently) for admin user-management + the mobile flag.

## rollbacks/

`rollback_get_member_earnings_vNN.sql` restores the function/behavior as it was
**before** the next migration (e.g. `…_v24.sql` reverts v24 back to v23). Run
one only if you need to undo the corresponding migration.

Branch cashier / branch stock undo scripts:

- `rollback_mobile_flag_v29.sql` — drop `profiles.mobile_enabled`.
- `rollback_branch_stock_v30.sql` — drop the whole branch-stock system.
- `rollback_branch_transfer_reports_v31.sql` — stop logging transfers to Reports.
- `rollback_branch_transfer_note_v32.sql` — drop the note from the Reports reason.
- `rollback_is_staff_v27.sql` — reverts the `is_staff()` change from v28.
- `rollback_earnings_sources_v34.sql` — drop the earnings-sources RPC (v34).
- `rollback_announcements_v36.sql` — ⚠️ **destructive**: drops the tables, and
  the tables _are_ the content (every announcement, everyone's saved list).
  The safe alternative is in the script's header — archive everything and
  switch birthday greetings off, which clears the members' screens without
  losing anything.
- `rollback_admin_fund_adjustments_v35.sql` — remove the adjust RPC and restore
  the v34 sources function. Does **not** reverse adjustments already posted —
  those are real ledger rows; post the opposite adjustment instead. Dropping
  `fund_adjustments` and `earnings_history.note` is deliberately commented out.

Announcement undo scripts (v39–v43) — each is paired with its migration and
carries the damage it does in its own header. Two are lossy: rolling back v40
destroys every record of who has seen what (re-applying then treats everything
as seen again), and rolling back v41 **deletes** saved items belonging to
accounts with no member row, i.e. every branch cashier's stars.

## diagnostics/

Read-only — safe on the live DB, write nothing.

- `diagnose_member_earnings.sql` — itemize one member's earnings (set the id at
  the top). Reconciles every peso to its source.
- `preview_v21…`, `preview_v22…` — impact previews for those specific migrations.

## maintenance/

⚠️ Destructive. `reset_tables.sql` / `deploy_reset.sql` wipe or reset data —
only for a fresh setup or a deliberate reset, never on live data you're keeping.

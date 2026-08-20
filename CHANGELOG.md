# What's New in GUTVita

A plain-language record of what changes in each update — written for everyone
who uses the app, not just the people who build it.

*Developers: the technical release notes (migrations, rollout order, commit
history) live in `docs/release_notes_technical.md`.*

---

## Next update — pending approval

> Currently being tested. Nothing here is live for everyone yet.

### 🏪 Branch stores can now hold their own stock

The biggest change in this update. Previously all stock sat in one place.
Now you can run branches properly:

- **Give stock to a branch.** An admin or main cashier hands out items to a
  branch. The quantity leaves the main stock and appears in that branch's
  own stock, so the totals always stay correct.
- **Branches sell from what they were given.** A branch cashier only sells
  what's actually in their branch — they can't accidentally sell stock that
  isn't there.
- **Send stock back.** Anything unsold can be returned to the main stock,
  or corrected if a count was wrong.
- **See everything in one place.** Admins get an overview of every branch's
  stock, plus a full history of who was given what, and when.
- **Every hand-out and return shows in Reports**, labelled "Branch Out" and
  "Branch In", with the branch name and any note that was added.

**New Branch Cashier accounts.** Admins create these like any other user.
By default they work on desktop only — if a branch needs to use a phone,
an admin can switch on mobile access for that specific account.

### 💰 Members can see where their earnings came from

Before, a member could see *how much* they earned but not *why*. Now the
Earnings screen breaks it down:

> **Chairman's Bonus — ₱6,000**
> • Maria Santos — ₱1,500 — 12 March
> • Jose Cruz — ₱1,500 — 8 March

Tap any earning type to see the individual credits and **the person each one
came from** — the member you referred, or the buyer whose purchase earned you
a commission. The numbers always add up to the totals shown at the top.

Each earning type shows its ten most recent credits, with a **"Show all"**
link if there are more — so the screen stays readable even for members with
a long history.

The Earnings screen now has a **Sources / History** switch at the top, so
you choose between *where the money came from* and *how your total changed
over time* instead of scrolling past both.

This should cut down a lot of "why is my total this amount?" questions,
because members can now answer it themselves.

**Also new: "Lifetime Earning"** — the total of everything you've ever
earned, before any withdrawals were taken out. Useful for seeing your
overall progress rather than just your current balance.

### 🧾 The buyer's package now shows when selling

When you pick a member in the POS, their availed package appears right under
their name — and it prints on the receipt too. If they haven't availed one,
it simply says "None". No more checking a separate screen to confirm what
package someone is on.

**Receipts now say GUTVita.** They previously showed "LZCAS", which didn't
match the name customers see anywhere else. Both the header and the footer
now read GUTVita.

### ⬇️ The app updates itself

You no longer need to be sent an installer for every update. The app checks
for new versions on its own and can download and install them for you.

For important updates (for example, one that changes how data is stored),
the update can be marked as **required** — you'll be asked to install it
before continuing, so everyone stays on a version that works.

### ⚡ Long lists are faster and smoother

Members, Transactions and Stocks lists now load the next page in the
background while you're reading the current one, so moving between pages
feels instant. While anything is still loading you'll see a soft placeholder
instead of the word "Loading…".

Branch stock transfers can also be filtered by branch and type, and load in
batches so the screen stays quick no matter how much history builds up.

### 🎨 A clearer Stocks on Hand for branches

Branch cashiers get a redesigned stock screen — at a glance you can see how
much stock is healthy, running low, or out, with search and filters to find
an item quickly.

### 🐛 Fixes

- **Lists no longer got stuck on "Loading…".** Anything past the first
  25 rows in Members, Transactions or Stocks used to show "Loading…"
  forever instead of the actual records. Fixed everywhere.
- **Request history counts were wrong.** The Approved / Rejected / All
  counters showed 0 even when approved withdrawals were listed right
  below them.
- **Chairman's Bonus was described incorrectly.** The app still said it was
  paid "every Friday", which hasn't been true for a while — it's earned once
  for each person you directly refer. The wording now matches how it's
  actually paid. *(How much anyone earns has not changed — only the
  description.)*
- **The update window could crash** when you closed it. It no longer does.
- **Inventory looked like it opened in an older layout.** The stats bar
  along the top (Products / Low / Out / Units) was hidden until its figures
  finished loading, so for a moment the page appeared without it and then
  everything jumped down. The bar now holds its place and fills in.

### Good to know

- **Some older earnings show "Source not recorded".** A few entries were
  created before the system started recording who each credit came from, so
  there's no name to show. Everything from here on will always show the
  source.
- **Upgrade bonuses show the package instead of a person** — for example
  "Upgrade Bonus — Ambassador Pack". These were never recorded with the name
  of the member who upgraded.

---

## Version 1.2 — 7 August 2026

The last update released to everyone. Changes before this date weren't
tracked in this file.

# What's New in GUTVita

A plain-language record of what changes in each update — written for everyone
who uses the app, not just the people who build it.

*Developers: the technical release notes (migrations, rollout order, commit
history) live in `docs/release_notes_technical.md`.*

---

## Next update — pending approval

> Currently being tested. Nothing here is live for everyone yet.

### 📣 Announcements

Admins can now post a notice — a holiday cut-off, a change to pack rates,
new pick-up hours — and have it reach everyone at once instead of a chain
of messages.

**Posting one.** Admin → Announcements → New Announcement. Write a title
and a message, choose who gets it (Everyone, Resellers only, or Members
only), and optionally set a date for it to stop showing. The screen tells
you how many accounts you are about to reach before you post.

**Reading them.** Members get an **Announcements** screen of their own.
The newest one also appears as a single line on their Overview, so people
see it without going looking.

> Write the title carefully — only the first line of it shows on the
> Overview, so the opening words have to carry the notice.

**Keeping one.** Tap the star on any announcement and it stays in a
**Saved** list even after it stops being current. Useful for a price list
or a set of hours someone wants to check back on. Saved items are marked
**Ended** so nobody mistakes an old notice for a live one.

Announcements are never really deleted — taking one down removes it from
everyone's screen but leaves saved copies alone. The screen tells you how
many people have saved it before you take it down.

### 🎂 Automatic birthday greetings

On a reseller's birthday, a greeting appears at the top of their Overview.
Nobody has to remember to send it.

It stays up for **30 days**, so a reseller who does not open the app on the
day itself still gets it. They can star it to keep it, the same as an
announcement.

Admins can change the wording, the number of days, or switch greetings off
entirely from Admin → Announcements.

> **Worth knowing:** the greeting only works for members whose birthday is
> recorded. The Announcements screen tells you how many resellers are
> missing one, so you can fill them in.

### 🐛 Fixes

- **Members could not open their Profile.** For accounts that are not
  resellers, tapping Profile in the sidebar showed the Overview instead.
  It now opens the Profile.

### 🛠️ Admins can correct a member's earnings

Sometimes a bonus is paid on something that turns out to be a mistake — a
duplicate referral, a cancelled sale, a wrong package. Until now the only
way to put that right was to edit the database by hand.

Admins now get an **Adjust Funds** button on a member's details. Pick which
earnings to correct (Direct Referral, Indirect Referral, Group Sales,
Chairman's Bonus or Upgrade Bonus), choose **Add** or **Deduct**, enter the
amount, and — this part is required — **write the reason**.

Before you confirm, the screen shows exactly what will change:

> **Chairman's Bonus**  ~~₱200~~ → **₱150**
> Their Total Earnings moves by −₱50.

A few things worth knowing about how it works:

- **Nothing is erased.** The original bonus stays in the member's history
  exactly as it was earned. The correction is added as its own separate
  entry, so the books always show what happened and in what order.
- **The reason is shown to the member.** It appears in their earnings
  breakdown next to the amount, so write it for them to read — a correction
  with no explanation is what generates the support message you were trying
  to avoid.
- **You can't push someone below zero.** If a deduction is larger than what
  they've earned in that category, it's refused and tells you the actual
  figure.
- **Admins only.** Cashiers and branch cashiers don't see the button.

### 🐛 Fixes

- **Corrections are no longer labelled "Withdrawal".** A drop in earnings
  was previously described as money paid out, even when it was an admin
  correction. The history now says what actually happened and shows the
  reason.
- **Deductions read properly.** A negative entry showed as "₱-300"; it now
  reads "−₱300" in red.

---

## Version 1.3.0 — 20 August 2026

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

Changes before this date weren't tracked in this file.

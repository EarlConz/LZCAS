# Online Shopping & Delivery — plan

Client ask, verbatim: Delivery Acc · Location/destination of member · Time/ETA
· Item/receiver · Add to cart · Confirmation of delivery · Mode of payment
(funds, or CoD with QR) · History payment · Chat · Set delivery fee.

This document maps each of those onto what already exists, decides what is
built next, and says why. The delivery account is first, so it gets the most
detail. Written 2026-09-14 against `origin/Delivery-System` at `c26df9f`.

---

## 0. What already exists (read this before anything else)

`origin/Delivery-System` (v47 + v48, one commit) already delivers:

| Area | State |
|---|---|
| Member location | **Done.** `members.latitude/longitude/location_updated_at` (v47). Address entry with GPS → Nominatim → IP fallback. |
| Add to cart / place order | **Done.** `member_marketplace_tab`, `active_orders_tab`, `create_delivery_order` RPC. |
| Delivery fee | **Done, per order.** Negotiated member ⇄ cashier through a state machine. |
| Order tables | `orders`, `order_items`. Realtime enabled on `orders`. |
| Cashier order screen | `delivery_orders_page.dart` (861 lines) — the **cashier's** view of orders, not a rider's. |

The order state machine as built:

```
Order Placed ──► Cashier Pricing & Negotiating ◄──► Member Negotiating
                            │
                            ▼
                         Agreed ──► Completed
                            │
                            └─────► Cancelled
```

Two facts about it shape everything below:

1. **Items have no shelf price.** The cashier prices them on receipt. A member
   does not know what they owe until the quote arrives. This is a business
   decision, not a bug — but it means *payment method cannot be chosen at
   checkout*, because the amount is unknown. It is chosen at **Agreed**.
2. **There is no delivery stage.** `Agreed → Completed` with the cashier doing
   everything and "Completed" meaning a POS receipt printed. The rider does not
   exist in this model. That is the hole "Delivery Acc" fills.

### ⚠️ Security debt in v48 that must be paid before a rider is added

These are not style points. They are the same bug class v5 fixed
("CRITICAL-2: reject non-staff callers") and v43 fixed last week.

- **`orders` and `order_items` have RLS disabled.** Every signed-in member can
  read every other member's **home address and GPS coordinates**, and every
  order's financials. The comment says "matches items/sales/members" — but
  those tables do not carry anyone's home location. This is a PII exposure
  larger than the `profiles` one already on the books.
- **All six RPCs are `SECURITY DEFINER` with no authorization check.**
  `cancel_delivery_order(id)` cancels any order for any caller.
  `complete_delivery_order(id)` completes any order. `cashier_send_quote` lets
  a member price their own order. A rider role makes this a three-party
  problem instead of two.
- v47 and v48 **do not record themselves** in `schema_migrations` (the v45
  convention). Not a security issue; noted so it is fixed in the same pass.

**Decision: authorization is designed into the state machine now, in a v49
that lands before any rider code.** Each transition RPC checks the caller's
relationship to the order — member owns it, cashier is assigned to it, rider is
assigned to it — and RLS on `orders` enforces the same for reads. Retrofitting
this after a third actor exists is strictly harder.

---

## 1. Delivery account — FIRST

### What it is

A new `profiles.role = 'delivery'`. A rider: takes an agreed order from a
cashier or branch, carries it to the member, hands it over, and — for CoD —
collects payment and later remits it.

**Not staff.** `is_staff()` grants POS, inventory and member data. A rider
needs none of it and must not have it. New helper `is_delivery()`, and the
existing `is_staff()` is left alone.

**Mobile-capable with no flag needed.** `AuthState._mobileBlocked` only
restricts `cashier`, `inventory` and un-granted `branch_cashier`; every other
role falls to `default: return false` and may use a phone. A rider therefore
needs no `mobile_enabled` grant, and the mobile toggle in the admin user
dialog correctly stays hidden for the role. (An earlier draft of this plan
said to default the flag `true` — unnecessary.)

### Admin integration

The Users screen is mostly enum-driven, so `UserRole.delivery` does most of the
work: the create dropdown is `UserRole.values` minus member/reseller, labels go
through `fromString`, and the `create-user` edge function passes `role`
through with no allowlist — nothing to redeploy. Three hand edits remain:

- the **role filter** dropdown (`admin_dashboard.dart` ~L905) is a hardcoded
  list — add Delivery;
- **`_roleColor`** (~L1438) is a hardcoded switch — give delivery a colour;
- **Cashier Locations** — add a **Riders** chip. Riders write their position
  to the same `profiles` columns while on a delivery, so this is the admin's
  "where are my riders now" view for free.

Announcements with audience `all` already reach riders through RLS (the policy
only needs a profile row). The reach count in the editor won't include them
and the rider app has no announcements screen — both fine to leave for v1.

### How an order reaches a rider

Decision: **the cashier dispatches.** When an order reaches *Agreed*, the
cashier who priced it picks a rider from a list. The alternative — riders
self-claim from a pool — is the Grab/Foodpanda model, and it needs enough
riders online at once to be worth building. This business has a few branches
and will start with a few riders; the cashier already owns the order and
already knows which rider is nearby. Revisit if rider count makes dispatch a
bottleneck.

The list the cashier picks from is riders **sorted by distance from the pickup
point**, using the rider's last known position. That reuses the v37 location
columns on `profiles` — but see §3 on how often a rider's position updates.

### The state machine, extended

```
Agreed ──► Assigned ──► Picked Up ──► Delivered ──► Completed
              │             │              │
              └─────────────┴──────────────┴──► Cancelled
```

| Status | Who sets it | What it means |
|---|---|---|
| `Assigned` | cashier | rider chosen; `delivery_id` set; rider notified |
| `Picked Up` | rider | rider has the goods; **ETA entered here** (§3) |
| `Delivered` | rider | rider says it is handed over |
| `Completed` | member (or QR scan, or cashier override) | receipt confirmed; payment settled (§6, §7) |

`Delivered` and `Completed` are separate on purpose. The rider's word and the
member's confirmation are two different facts, and disputes live in the gap
between them.

### Columns added to `orders`

```
delivery_id        uuid            -- profiles.id of the rider
assigned_at        timestamptz
picked_up_at       timestamptz
eta_at             timestamptz     -- rider's estimate, set at pickup, updatable
delivered_at       timestamptz
receiver_name      text            -- §4; defaults to member's own name
receiver_contact   text
confirmed_by       uuid            -- §6
confirmed_at       timestamptz
confirmation_method text check in ('member_tap','qr','cashier_override')
payment_method     text check in ('funds','cod')          -- §7
payment_status     text check in ('unpaid','paid') default 'unpaid'
paid_at            timestamptz
payment_transaction_id bigint     -- member_transactions row, for funds
cod_remitted_at    timestamptz     -- §8; cashier confirms cash received from rider
cod_remitted_to    uuid
```

### RPCs added (each checks the caller)

```
cashier_assign_rider(order_id, rider_id)      caller is_staff() AND orders.cashier_id = auth.uid()
delivery_pickup(order_id, eta_at)             caller is_delivery() AND orders.delivery_id = auth.uid()
delivery_update_eta(order_id, eta_at)         same
delivery_mark_delivered(order_id)             same
delivery_update_position(lat, lng)            caller is_delivery(); writes own profiles row only
```

### RLS on `orders` (part of v49)

- member: rows where `member_id` maps to their `profiles.member_id`
- cashier / branch cashier: rows where `cashier_id = auth.uid()`, plus
  unassigned *Order Placed* rows (so they can pick them up)
- rider: rows where `delivery_id = auth.uid()`
- admin: everything

`order_items` follows its parent order.

### What the rider's app shows

Four screens, all phone-width first (see [[lzcas-check-mobile-layout]]):

1. **My Deliveries** — Assigned / Picked Up, newest first. Each card: order
   number, receiver, distance, ETA if set, payment method badge (CoD needs
   cash handling; funds does not).
2. **Order detail** — items with quantities, receiver name + contact (tap to
   call), delivery address, map with the pin, **"Open in Google Maps"** (turn-
   by-turn — `flutter_map` has no routing and should not grow any), chat (§9),
   and the one action that is valid for the current status.
3. **Handover** — for funds: "Mark delivered", then the member confirms on
   their side. For CoD: **scan the member's order QR** (§7), which is both
   confirmation and payment in one gesture.
4. **History** — delivered orders, with a **CoD collected / remitted** tally
   so the rider and the cashier agree on what cash is owed.

### Account creation

Admin creates riders the same way as any other account — the `create-user`
edge function. `UserRole.fromString` throws on unknown roles, so **the app
build carrying `UserRole.delivery` must ship before the first rider account
exists**, same rule as `branch_cashier` in v28.

---

## 2. Location / destination of member — done

v47. The order **snapshots** `delivery_address` and coordinates at placement,
so a member updating their location later does not move an order already in
flight. That is the right behaviour; leave it.

One addition, cheap and high-value: the rider's order detail opens the
destination in the phone's maps app for turn-by-turn. No routing dependency.

---

## 3. Time / ETA

There is no routing engine, and adding one (OSRM, Google Directions) is
another free-endpoint or paid dependency — the same concern already open
against Nominatim.

Decision: **the rider enters the ETA at pickup**, as a time ("about 4:30") or
duration ("~30 min"), stored as `orders.eta_at`, and can update it. The member
sees it live via Realtime. Honest, needs nothing external, and a person who
knows the road is a better estimator than a straight line.

A straight-line distance from the rider's position to the destination can be
shown as a hint — it comes free from the existing haversine code.

**Rider position updates.** The cashier's dispatch list and the member's
"where is my order" both want the rider's position. The v37 columns on
`profiles` were built for a *saved* location that changes once a year; a rider
moves constantly. For v1: the rider's app writes its position to those same
columns **every 60 seconds while an order is Picked Up**, and never otherwise.
That is enough for dispatch and for a rough "rider is 2 km away," costs
nothing, and does not track anyone off-shift. A live-tracking map is explicitly
*not* in scope.

---

## 4. Item / receiver

Items are done (`order_items`). **Receiver** is new: the person receiving may
not be the member (a relative at home). Two fields at checkout, defaulting to
the member's own name and `contact_no`, editable per order. The rider sees
them. Stored on the order, not the member, because the receiver can differ
per order.

---

## 5. Add to cart — done

Teammate's. Not touched. One UX note worth passing to the client: because
items carry no price until the cashier quotes, the cart cannot show a total,
and the member's first sight of a number is the quote. If that surprises
people, the fix is business (publish prices), not code.

---

## 6. Confirmation of delivery

Two-sided, and the two sides are recorded separately:

- Rider marks **Delivered** (`delivered_at`).
- Member confirms **Completed**, by one of:
  - **`member_tap`** — "I received it" in their app. Used for funds-paid orders.
  - **`qr`** — the rider scanned the member's order QR at handover. Used for
    CoD, where it is also the payment confirmation (§7).
  - **`cashier_override`** — the cashier closes it manually, with a reason,
    when a member never confirms. Logged as such.

No auto-complete on a timer. Orders that sit in *Delivered* are visible to the
cashier as needing attention, which is the right outcome — a timer would hide
exactly the orders that have a problem.

---

## 7. Mode of payment

Chosen at **Agreed**, not at checkout — the total is not known until then
(§0). The member's Agree screen shows the locked `final_total` and asks
funds or CoD.

### Funds

New RPC `pay_order_with_funds(order_id, source_bucket)`:

1. caller is the order's member; order is *Agreed*; `payment_status = 'unpaid'`
2. `get_member_earnings` for the caller; refuse if the chosen bucket <
   `final_total`
3. insert **one negative `member_transactions` row** — append-only, exactly
   like v35's adjustments, `item_name` prefixed so `get_member_earnings`
   subtracts it and `get_member_earnings_sources` lists it as
   "Order #… — delivery purchase"
4. set `payment_method='funds'`, `payment_status='paid'`, `paid_at`,
   `payment_transaction_id`

All in one transaction; a failure anywhere leaves both the balance and the
order untouched. `source_bucket` uses the same `('total_earnings','balance')`
choice `withdrawal_requests` already offers, so the member's mental model does
not change.

### Cash on delivery, with QR

**Per-order QR, not the member's identity QR.** `members.qr` is a persistent
identifier printed on things; anyone who has seen it could confirm a delivery.
Instead the order carries a single-use `cod_nonce` (generated at Agreed, shown
as a QR in the member's app). At handover the rider scans it →
`confirm_cod_delivery(order_id, nonce)`:

1. caller `is_delivery()` and `orders.delivery_id = auth.uid()`
2. nonce matches and has not been used
3. set `Completed`, `confirmation_method='qr'`, `payment_status='paid'`,
   `paid_at`, `confirmed_at`, clear the nonce

One scan is receipt confirmation *and* payment record. The member has to be
physically present with their phone, which is the whole point.

**Refusal**: if the member refuses the goods, the rider marks it and the order
goes to *Cancelled* with a reason — the cashier sees it and restocks.

### Recording the sale

At *Completed*, one `sales` row per line item, same as today's "Completed =
recorded in sales" — extended to note `payment_method` so reports can split
funds from cash.

---

## 8. History / payment

Three audiences, one table:

- **Member** — their orders, any status, with method, amount, date. Funds
  purchases also appear in their earnings breakdown as negative sources, so
  the two views reconcile.
- **Admin** — all orders; filter by status, method, rider, cashier, date.
- **Rider** — delivered orders with a **CoD tally**: collected, remitted,
  outstanding. `cod_remitted_at / cod_remitted_to` are set by the **cashier**
  when the rider hands over cash — not by the rider. The person receiving the
  money records it.

---

## 9. Chat

Per-order, participants only. Not general messaging.

```
order_messages (
  id bigint identity,
  order_id uuid references orders,
  sender_id uuid,           -- profiles.id
  body text not null,
  created_at timestamptz
)
```

Realtime enabled. RLS: read/write only if the caller is the order's member,
cashier, or rider. Text only in v1; no attachments, no read receipts, no
typing indicators. The structured negotiation stays — chat is for "gate code
is 1234" and "I'm at the corner," not for the fee.

Retention: messages live as long as the order does. Orders are never deleted
(they are financial records), so neither are messages.

---

## 10. Set delivery fee

Per-order negotiation is done. What the client likely means by "set" is a
**default** the cashier starts from. Two `app_config` keys, admin-editable in
the existing settings screen, admin-only to write (v46):

```
delivery_base_fee       e.g. 50
delivery_fee_per_km     e.g. 10
```

The cashier's quote screen pre-fills `base + per_km × straight-line distance`
and the cashier edits it. Negotiation continues exactly as built.

---

## Build order

Each step is shippable on its own and useful without the next.

| # | Migration | App | Why this order |
|---|---|---|---|
| 1 | ✅ **v49** orders authorization: RLS on `orders`/`order_items`, caller checks in all six RPCs, ledger rows for v47/v48 | — | Prerequisite. Adding a rider to unauthorized RPCs makes the hole bigger. |
| 2 | ✅ **v50** `delivery` role, `is_delivery()`, order columns (§1), new statuses, dispatch/pickup/deliver RPCs, receiver fields, ETA | ✅ `UserRole.delivery`, rider screens, cashier dispatch, member sees rider + ETA, admin filter/colour/Riders chip | **Ship the app before the first rider account exists.** |
| 3 | **v51** payment: `pay_order_with_funds`, `cod_nonce`, `confirm_cod_delivery`, `sales` gets `payment_method` | payment choice at Agreed, member QR screen, rider scanner, confirmation | Depends on the rider existing. |
| 4 | **v52** `order_messages` + Realtime + RLS | chat sheet on order detail, all three roles | Independent; could go earlier, but riders make it worth having. |
| 5 | `app_config` fee keys (no migration — `insert … on conflict do nothing` can ride on v52) | settings fields, quote pre-fill | Small. |

Every migration from v49 on carries the ledger footer.

**Built 2026-09-14 (v49 + v50 + app), on branch `delivery-account` from
`origin/Delivery-System`.** What was NOT built, and why:

- **Receiver fields at checkout.** The columns exist and the rider's screens
  read them, but the member's cart does not yet ask "who is receiving?" — that
  is the teammate's marketplace code, and it defaults to the member correctly
  until it does.
- **Handover QR scan.** The rider's Handover is a plain "Mark delivered" with a
  confirmation dialog. The scanner is v51's — it only means something once
  there is a payment to confirm with it, and a fake scanner that always
  succeeds is worse than a button that says what it does.
- **`sales` on member confirmation.** See the README's v50 note. Until v51, an
  order the member confirms is Completed but has no `sales` rows; the cashier
  override path records them client-side as v48 did.
- **Delivery notifications.** The teammate's `delivery_notification_service`
  chimes on order events; it does not yet know the rider states. Realtime
  still refreshes every screen — the rider just does not get a sound when
  assigned. Small; do it with v52's chat, which needs the same plumbing.

---

## Questions for the client, in order of how much they change the build

1. **Who pays the rider, and how?** Nothing above computes rider earnings. If
   riders are on commission per delivery, that is a ledger — another
   append-only `member_transactions`-style table — and it should be designed
   with §7, not after.
2. **Can a member pay part funds, part cash?** The plan says no: one method
   per order. Split payment roughly doubles §7.
3. **Do riders work for one branch, or float?** Affects the dispatch list.
   The plan assumes any cashier can assign any rider.
4. **What happens to a CoD order the member refuses?** The plan cancels and
   restocks. If the client wants a re-delivery attempt or a fee charged, that
   is a state we have not drawn.

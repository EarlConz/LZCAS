// lib/pages/delivery/delivery_orders_parts.dart
//
// The pieces the Delivery Orders page and its order pane share: which
// stage an order is in, the stage tiles, the status pill, the progress
// stepper, the section card, and rider ranking.
//
// "Stage" is the page's word, not the database's. The database has nine
// statuses; the cashier has six questions — is there something to price,
// a counter to answer, an order to dispatch, one on the road, cash to take
// in, or nothing left to do. Stages group statuses by WHO acts next, which
// is what a queue should be sorted by.

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';

// ─── Stages ─────────────────────────────────────────────────────────────────

enum OrderStage {
  toPrice('To price', 'To price', Color(0xFFFF6700)),
  negotiating('Negotiating', 'Negotiating', StockpileColors.secondary500),
  toDispatch('Ready to dispatch', 'To dispatch', StockpileColors.success),
  onTheWay('Out for delivery', 'On the way', Color(0xFFB24800)),
  cash('Cash to remit', 'Cash', StockpileColors.danger),
  history('History', 'History', StockpileColors.mutedText);

  const OrderStage(this.label, this.shortLabel, this.dot);
  final String label;

  /// For the phone's narrower tiles.
  final String shortLabel;
  final Color dot;
}

extension OrderStageOf on DeliveryOrder {
  /// Where this order sits in the cashier's queue. A completed cash order
  /// whose money is still with the rider is `cash`, not `history`: it is
  /// finished for the member and not yet finished for the business.
  OrderStage get stage {
    if (awaitingRemittance) return OrderStage.cash;
    return switch (status) {
      DeliveryOrderStatus.orderPlaced => OrderStage.toPrice,
      DeliveryOrderStatus.cashierPricing ||
      DeliveryOrderStatus.memberNegotiating => OrderStage.negotiating,
      DeliveryOrderStatus.agreed => OrderStage.toDispatch,
      DeliveryOrderStatus.assigned ||
      DeliveryOrderStatus.pickedUp ||
      DeliveryOrderStatus.delivered => OrderStage.onTheWay,
      _ => OrderStage.history,
    };
  }

  /// Whether the cashier is the one holding things up. A quote waiting on
  /// the member, or an order on a rider's bike, is not.
  bool get needsCashier =>
      status == DeliveryOrderStatus.orderPlaced ||
      status == DeliveryOrderStatus.memberNegotiating ||
      status == DeliveryOrderStatus.agreed ||
      awaitingRemittance;

  /// How long it has sat in its current status. `updated_at` is touched by
  /// every write (v48's trigger), which is exactly "since the last move".
  Duration get waiting =>
      DateTime.now().difference((updatedAt ?? createdAt ?? DateTime.now()).toLocal());

  /// The member's first name, for sentences like "Maria sees ₱1,600".
  String get memberFirstName {
    final n = (memberName ?? '').trim();
    if (n.isEmpty) return 'The member';
    return n.split(RegExp(r'\s+')).first;
  }
}

/// "18 min", "2 h 5 min", "3 d" — waiting time in the fewest words.
String formatWaiting(Duration d) {
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 24) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  return '${d.inDays} d';
}

/// Past this, a needs-you order's waiting time turns orange. One constant so
/// the list and the tiles agree on what "waiting too long" means.
const kWaitingTooLong = Duration(minutes: 15);

// ─── Colours this page adds ─────────────────────────────────────────────────

/// Caption grey, darkened from `mutedText` (#8E8E9A), which reads at about
/// 3:1 on white — below the 4.5:1 small text needs. Local to this page for
/// now; worth promoting to the theme.
const kCaption = Color(0xFF6E6E7A);

/// Readable orange for text. `primary900` is a fill colour: as small text
/// on white or on `primary50` it fails contrast.
const kOrangeText = Color(0xFFB24800);

const kDangerText = Color(0xFFB91C1C);

// ─── Status pill ────────────────────────────────────────────────────────────

class StagePill extends StatelessWidget {
  final String text;
  final Color dot;
  final bool isDark;

  const StagePill({
    super.key,
    required this.text,
    required this.dot,
    required this.isDark,
  });

  /// The pill for an order: its stage's colour, with wording precise
  /// enough to tell "Counter-offer" from "Quote sent".
  factory StagePill.forOrder(DeliveryOrder o, {required bool isDark}) {
    final text = switch (o.status) {
      DeliveryOrderStatus.orderPlaced => 'To price',
      DeliveryOrderStatus.cashierPricing => 'Quote sent',
      DeliveryOrderStatus.memberNegotiating => 'Counter-offer',
      DeliveryOrderStatus.agreed => 'Ready to dispatch',
      DeliveryOrderStatus.assigned => 'Rider assigned',
      DeliveryOrderStatus.pickedUp => 'On the way',
      DeliveryOrderStatus.delivered => 'Awaiting member',
      DeliveryOrderStatus.completed =>
        o.awaitingRemittance ? 'Cash with rider' : 'Completed',
      DeliveryOrderStatus.cancelled => 'Cancelled',
      _ => o.status,
    };
    return StagePill(text: text, dot: o.stage.dot, isDark: isDark);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: StockpileFonts.satoshi(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? StockpileColors.darkTextPrimary
                  : StockpileColors.bodyText,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stage tile ─────────────────────────────────────────────────────────────

/// One filter tile: the stage, its count (or amount), and one line of why
/// it matters right now. Selected tiles take the app's accent.
class StageTile extends StatelessWidget {
  final OrderStage stage;
  final String value;
  final String hint;
  final bool hintUrgent;
  final bool selected;
  final bool compact;
  final bool isDark;
  final VoidCallback onTap;

  const StageTile({
    super.key,
    required this.stage,
    required this.value,
    required this.hint,
    required this.selected,
    required this.isDark,
    required this.onTap,
    this.hintUrgent = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? (isDark ? StockpileColors.primary900.withAlpha(40) : StockpileColors.primary50)
        : (isDark ? StockpileColors.darkSurface : StockpileColors.surface);
    final border = selected
        ? StockpileColors.primary900
        : (isDark ? StockpileColors.darkDivider : StockpileColors.divider);
    final text = isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final sub = isDark ? StockpileColors.darkTextMuted : kCaption;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          side: BorderSide(color: border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          child: Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 12, vertical: 10)
                : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: stage.dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        (compact ? stage.shortLabel : stage.label).toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StockpileFonts.satoshi(
                          fontSize: compact ? 10 : 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: isDark
                              ? StockpileColors.darkTextMuted
                              : StockpileColors.bodyText,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 4 : 6),
                Text(
                  value,
                  maxLines: 1,
                  style: StockpileFonts.satoshi(
                    fontSize: compact ? 22 : 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: text,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 6),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      fontWeight: hintUrgent ? FontWeight.w600 : FontWeight.w400,
                      color: hintUrgent ? kOrangeText : sub,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Progress stepper ───────────────────────────────────────────────────────

/// Placed → Quote → Agreed → Dispatched → Delivered → Completed, with the
/// current step ringed and a word under it saying who it is waiting on.
class OrderStepper extends StatelessWidget {
  final DeliveryOrder order;
  final bool isDark;
  final bool compact;

  const OrderStepper({
    super.key,
    required this.order,
    required this.isDark,
    this.compact = false,
  });

  static const _labels = [
    'Placed',
    'Quote',
    'Agreed',
    'Dispatched',
    'Delivered',
    'Completed',
  ];

  /// Index of the step in progress; 6 when everything is done, null when
  /// cancelled (no step is "current" on an order that stopped).
  int? get _current => switch (order.status) {
    DeliveryOrderStatus.orderPlaced ||
    DeliveryOrderStatus.cashierPricing ||
    DeliveryOrderStatus.memberNegotiating => 1,
    DeliveryOrderStatus.agreed || DeliveryOrderStatus.assigned => 3,
    DeliveryOrderStatus.pickedUp => 4,
    DeliveryOrderStatus.delivered => 5,
    DeliveryOrderStatus.completed => 6,
    _ => null,
  };

  /// Who the current step is waiting on.
  String? get _waitingOn => switch (order.status) {
    DeliveryOrderStatus.orderPlaced ||
    DeliveryOrderStatus.memberNegotiating ||
    DeliveryOrderStatus.agreed => 'You',
    DeliveryOrderStatus.cashierPricing ||
    DeliveryOrderStatus.delivered => 'Member',
    DeliveryOrderStatus.assigned => 'Rider',
    DeliveryOrderStatus.pickedUp =>
      order.etaAt == null ? 'Rider' : 'ETA ${_clock(order.etaAt!)}',
    _ => null,
  };

  /// The time under a finished step, where the order records one.
  DateTime? _timeOf(int i) => switch (i) {
    0 => order.createdAt,
    3 => order.assignedAt,
    4 => order.deliveredAt,
    5 => order.confirmedAt ?? order.paidAt,
    _ => null,
  };

  static String _clock(DateTime t) {
    final l = t.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final dark = isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
    final line = isDark ? StockpileColors.darkDivider : StockpileColors.divider;
    final done = isDark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;

    final children = <Widget>[];
    for (var i = 0; i < _labels.length; i++) {
      if (i > 0) {
        children.add(
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(top: 10),
              color: current != null && i <= current ? done : line,
            ),
          ),
        );
      }
      final isDone = current != null && i < current;
      final isCurrent = current == i;
      final allDone = current == 6;
      final time = _timeOf(i);

      Widget dot;
      if (isDone) {
        dot = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: allDone && i == 5 ? StockpileColors.success : done,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            size: 14,
            color: isDark ? StockpileColors.darkBg : Colors.white,
          ),
        );
      } else if (isCurrent) {
        dot = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: StockpileColors.primary50,
            shape: BoxShape.circle,
            border: Border.all(color: StockpileColors.primary900, width: 2),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: StockpileColors.primary900,
              shape: BoxShape.circle,
            ),
          ),
        );
      } else {
        dot = Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: isDark ? StockpileColors.darkSurface : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: line, width: 2),
          ),
        );
      }

      final sub = isCurrent
          ? _waitingOn
          : (isDone && time != null ? _clock(time) : null);

      children.add(
        SizedBox(
          width: compact ? 52 : 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              dot,
              const SizedBox(height: 4),
              Text(
                _labels[i],
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: StockpileFonts.satoshi(
                  fontSize: compact ? 10 : 11,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                  color: isCurrent
                      ? dark
                      : (isDone
                            ? (isDark
                                  ? StockpileColors.darkTextMuted
                                  : StockpileColors.bodyText)
                            : kCaption),
                ),
              ),
              if (sub != null)
                Text(
                  sub,
                  maxLines: 1,
                  softWrap: false,
                  style: StockpileFonts.satoshi(
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                    color: isCurrent ? kOrangeText : kCaption,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: current == null
          ? 'Order cancelled'
          : current >= 6
          ? 'Order completed'
          : 'Step ${current + 1} of 6, ${_labels[current]}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

// ─── Section card ───────────────────────────────────────────────────────────

/// A titled block inside the order pane.
class PaneSection extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget child;
  final bool isDark;

  const PaneSection({
    super.key,
    required this.title,
    required this.child,
    required this.isDark,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                title,
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? StockpileColors.darkTextPrimary
                      : StockpileColors.darkText,
                ),
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: StockpileFonts.satoshi(fontSize: 12, color: kCaption),
              ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

/// A tinted one-line explanation with an icon — payment, notes, warnings.
class PaneNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Color tint;
  final Color iconColor;
  final bool dashed;
  final bool isDark;

  const PaneNote({
    super.key,
    required this.icon,
    required this.title,
    required this.isDark,
    this.body,
    this.tint = StockpileColors.primary50,
    this.iconColor = kOrangeText,
    this.dashed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: dashed ? null : (isDark ? iconColor.withAlpha(30) : tint),
        borderRadius: BorderRadius.circular(12),
        border: dashed
            ? Border.all(
                color: isDark ? StockpileColors.darkDivider : const Color(0xFFD6D6DD),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: StockpileFonts.satoshi(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? StockpileColors.darkTextPrimary
                        : StockpileColors.darkText,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    body!,
                    style: StockpileFonts.satoshi(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark
                          ? StockpileColors.darkTextMuted
                          : StockpileColors.bodyText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Rider ranking ──────────────────────────────────────────────────────────

/// A rider as a dispatch choice: how far from the branch, whether they are
/// already carrying something, and whether their position is fresh.
class RiderCandidate {
  final UserProfile rider;
  final double? meters;
  final bool busy;

  const RiderCandidate(this.rider, this.meters, this.busy);

  bool get hasPosition => rider.latitude != null && rider.longitude != null;

  /// A ping in the last 5 minutes: on the road right now.
  bool get isLive {
    final at = rider.locationUpdatedAt;
    return at != null &&
        DateTime.now().difference(at.toLocal()) < const Duration(minutes: 5);
  }
}

/// Riders in the order a cashier should consider them: free before busy,
/// then nearest to [fromLat]/[fromLng], and a rider who has never sent a
/// position last. Distances are measured from the BRANCH, because the rider
/// comes to the branch first to collect the order.
List<RiderCandidate> rankRiders(
  List<UserProfile> riders, {
  required double? fromLat,
  required double? fromLng,
  Set<String> busyIds = const {},
}) {
  final list = [
    for (final r in riders)
      RiderCandidate(
        r,
        fromLat == null || fromLng == null || r.latitude == null || r.longitude == null
            ? null
            : Geolocator.distanceBetween(fromLat, fromLng, r.latitude!, r.longitude!),
        busyIds.contains(r.id),
      ),
  ];
  list.sort((a, b) {
    if (a.busy != b.busy) return a.busy ? 1 : -1;
    final da = a.meters, db = b.meters;
    if (da == null && db == null) return a.rider.username.compareTo(b.rider.username);
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  });
  return list;
}

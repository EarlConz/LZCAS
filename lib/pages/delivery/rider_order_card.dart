// lib/pages/delivery/rider_order_card.dart
//
// One order as the rider sees it in a list. Shared by My Deliveries (full)
// and History (compact) so the two never drift apart.

import 'package:flutter/material.dart';

import 'package:lzcas/db/db.dart';
import 'package:lzcas/theme.dart';
import 'package:lzcas/utils/fonts.dart';
import 'package:lzcas/utils/formatters.dart';

class RiderOrderCard extends StatelessWidget {
  final DeliveryOrder order;

  /// Straight-line distance from the rider to the drop-off, or null when
  /// the rider's position is unknown. A hint, not a route.
  final double? metersAway;

  final bool isDark;

  /// The one order on its way gets the accent border so it is the first
  /// thing the eye lands on when the phone comes out of a pocket.
  final bool highlighted;

  /// History rows: one line, amount on the right, no address.
  final bool compact;

  final VoidCallback onTap;

  const RiderOrderCard({
    super.key,
    required this.order,
    required this.metersAway,
    required this.isDark,
    required this.onTap,
    this.highlighted = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final body = isDark
        ? StockpileColors.darkTextBody
        : StockpileColors.bodyText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final divider = isDark
        ? StockpileColors.darkDivider
        : StockpileColors.divider;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: isDark ? StockpileColors.darkSurface : StockpileColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlighted ? StockpileColors.primary200 : divider,
              ),
            ),
            child: compact
                ? _compactRow(text, muted)
                : _fullCard(text, body, muted, divider),
          ),
        ),
      ),
    );
  }

  Widget _fullCard(Color text, Color body, Color muted, Color divider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Order ${order.shortId}',
                style: StockpileFonts.satoshi(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
            ),
            PaymentChip(order: order, isDark: isDark),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          order.receiverDisplayName,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: text,
          ),
        ),
        if ((order.deliveryAddress ?? '').isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            order.deliveryAddress!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              height: 1.45,
              color: body,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Divider(height: 1, color: divider),
        const SizedBox(height: 8),
        Row(
          children: [
            if (order.isPickedUp && order.etaAt != null) ...[
              Icon(Icons.schedule_rounded, size: 14, color: muted),
              const SizedBox(width: 5),
              Text(
                'ETA ${formatTimeOfDay(order.etaAt!)}',
                style: StockpileFonts.satoshi(fontSize: 12, color: body),
              ),
              const SizedBox(width: 12),
            ],
            if (metersAway != null) ...[
              Icon(Icons.place_outlined, size: 14, color: muted),
              const SizedBox(width: 5),
              Text(
                formatDistance(metersAway!),
                style: StockpileFonts.satoshi(fontSize: 12, color: body),
              ),
            ],
            const Spacer(),
            StatusChip(status: order.status, isDark: isDark),
          ],
        ),
      ],
    );
  }

  Widget _compactRow(Color text, Color muted) {
    final when = order.confirmedAt ?? order.deliveredAt ?? order.updatedAt;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order.shortId} · ${order.receiverDisplayName}',
                overflow: TextOverflow.ellipsis,
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: order.isCancelled ? muted : text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatRelativeDate(when),
                style: StockpileFonts.satoshi(fontSize: 12, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(order.finalTotal),
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: order.isCancelled ? muted : text,
              ),
            ),
            const SizedBox(height: 4),
            order.isCancelled
                ? const StatusChip(
                    status: DeliveryOrderStatus.cancelled,
                    isDark: false,
                  )
                : PaymentChip(order: order, isDark: isDark),
          ],
        ),
      ],
    );
  }
}

/// CoD in the warm tint (cash to handle), funds in the cool one (nothing to
/// handle), and a quiet "not set" until v51 gives orders a payment method.
class PaymentChip extends StatelessWidget {
  final DeliveryOrder order;
  final bool isDark;
  const PaymentChip({super.key, required this.order, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = order.isCod
        ? (
            StockpileColors.primary50,
            const Color(0xFFB24800),
            'CoD · ${formatMoney(order.finalTotal)}',
          )
        : order.isFunds
        ? (
            StockpileColors.secondary50,
            StockpileColors.secondary500,
            order.isPaid ? 'Paid · funds' : 'Funds',
          )
        : (
            isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
            isDark ? StockpileColors.darkTextMuted : StockpileColors.mutedText,
            formatMoney(order.finalTotal),
          );
    return _chip(bg, fg, label);
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  final bool isDark;
  const StatusChip({super.key, required this.status, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      DeliveryOrderStatus.pickedUp => (
        StockpileColors.primary50,
        const Color(0xFFB24800),
      ),
      DeliveryOrderStatus.delivered => (
        StockpileColors.secondary50,
        StockpileColors.secondary500,
      ),
      DeliveryOrderStatus.completed => (
        StockpileColors.successBg,
        const Color(0xFF15803D),
      ),
      DeliveryOrderStatus.cancelled => (
        StockpileColors.dangerBg,
        const Color(0xFFB91C1C),
      ),
      _ => (
        isDark ? StockpileColors.darkInputBg : StockpileColors.inputBg,
        isDark ? StockpileColors.darkTextBody : StockpileColors.bodyText,
      ),
    };
    return _chip(bg, fg, status);
  }
}

Widget _chip(Color bg, Color fg, String label) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
  decoration: BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(100),
  ),
  child: Text(
    label,
    style: StockpileFonts.satoshi(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: fg,
    ),
  ),
);

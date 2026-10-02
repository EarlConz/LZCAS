// lib/pages/member/member_order_kit.dart
//
// What the member's shop screens share, from the "Member Shop & Orders"
// design: how an order reads to a MEMBER (its label, whether it is waiting
// on them, its progress), the small pieces that show it, and every action a
// member can take on an order. Active Orders, the order's own screen and
// the Marketplace all use these, so an order reads the same everywhere.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney;
import 'order_payment_sheet.dart';

export '../../widgets/product_tile.dart' show ProductTile;

// ─── Colours ────────────────────────────────────────────────────────────────

/// The shop's colours, light and dark. Text colours are the darker variants:
/// the theme's `mutedText` and `primary900` fail contrast as small text.
class ShopColors {
  final bool dark;
  const ShopColors(this.dark);

  factory ShopColors.of(BuildContext context) =>
      ShopColors(Theme.of(context).brightness == Brightness.dark);

  Color get text =>
      dark ? StockpileColors.darkTextPrimary : StockpileColors.darkText;
  Color get muted =>
      dark ? StockpileColors.darkTextMuted : const Color(0xFF6E6E7A);
  Color get line =>
      dark ? StockpileColors.darkDivider : const Color(0xFFE8E8EC);
  Color get surface => dark ? StockpileColors.darkSurface : Colors.white;
  Color get ground => dark ? StockpileColors.darkBg : const Color(0xFFFAFAFA);
  Color get soft =>
      dark ? StockpileColors.darkInputBg : const Color(0xFFF5F5F8);
  Color get accentText =>
      dark ? StockpileColors.primary500 : const Color(0xFFB24800);
  Color get accentSoft =>
      dark ? StockpileColors.primary900.withAlpha(36) : const Color(0xFFFFF7DF);
  Color get accent => StockpileColors.primary900;
}

// ─── How an order reads to a member ─────────────────────────────────────────

enum OrderTone { needsYou, inProgress, done, stopped }

extension MemberOrderView on DeliveryOrder {
  /// Finished one way or the other: the Past list.
  bool get isPast => isCompleted || isCancelled;

  /// The member is the one holding it up: a quote to answer, a payment to
  /// choose or send, a delivery to confirm.
  bool get memberMustAct {
    if (status == DeliveryOrderStatus.cashierPricing || isDelivered) {
      return true;
    }
    if (!isAgreed || isPaid) return false;
    if (isOutside) return paymentDetailsAt != null && paymentSentAt == null;
    return !isCod;
  }

  /// The status in the member's words.
  String get memberLabel => switch (status) {
    DeliveryOrderStatus.orderPlaced => 'Waiting for prices',
    DeliveryOrderStatus.cashierPricing => 'Quote ready',
    DeliveryOrderStatus.memberNegotiating => 'Offer sent',
    DeliveryOrderStatus.agreed =>
      isPaid
          ? (isCourier ? 'Paid · booking $routeLabel' : 'Paid · preparing')
          : isCod
          ? 'Cash on delivery'
          : isOutside
          ? (paymentSentAt != null
                ? 'Payment sent'
                : paymentDetailsAt != null
                ? 'Send your payment'
                : 'Waiting for pay details')
          : 'Choose how to pay',
    DeliveryOrderStatus.assigned => 'Rider assigned',
    DeliveryOrderStatus.pickedUp => 'On the way',
    DeliveryOrderStatus.delivered => 'Delivered',
    DeliveryOrderStatus.shipped => 'Shipped · $routeLabel',
    DeliveryOrderStatus.completed => 'Completed',
    DeliveryOrderStatus.cancelled => 'Cancelled',
    _ => status,
  };

  OrderTone get tone => isCancelled
      ? OrderTone.stopped
      : isCompleted
      ? OrderTone.done
      : memberMustAct
      ? OrderTone.needsYou
      : OrderTone.inProgress;

  /// 0 Placed · 1 Priced · 2 Agreed · 3 On the way / Shipped · 4 Delivered
  /// / Received; 5 when complete; null when cancelled.
  int? get progressStep => switch (status) {
    DeliveryOrderStatus.orderPlaced => 0,
    DeliveryOrderStatus.cashierPricing ||
    DeliveryOrderStatus.memberNegotiating => 1,
    DeliveryOrderStatus.agreed => 2,
    DeliveryOrderStatus.assigned ||
    DeliveryOrderStatus.pickedUp ||
    DeliveryOrderStatus.shipped => 3,
    DeliveryOrderStatus.delivered => 4,
    DeliveryOrderStatus.completed => 5,
    _ => null,
  };

  List<String> get progressLabels => isCourier
      ? const ['Placed', 'Priced', 'Agreed', 'Shipped', 'Received']
      : const ['Placed', 'Priced', 'Agreed', 'On the way', 'Delivered'];

  int get itemCount => items.fold(0, (n, it) => n + it.quantity);

  /// A member may back out until the goods are moving.
  bool get memberCanCancel => isOpen || isAgreed || (isAssigned && !isCourier);
}

// ─── Small pieces ───────────────────────────────────────────────────────────

class OrderPill extends StatelessWidget {
  final DeliveryOrder order;
  const OrderPill(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    final (Color fg, Color bg) = switch (order.tone) {
      OrderTone.needsYou => (c.accentText, c.accentSoft),
      OrderTone.inProgress => (
        StockpileColors.secondary500,
        c.dark
            ? StockpileColors.secondary500.withAlpha(40)
            : StockpileColors.secondary50,
      ),
      OrderTone.done => (
        c.dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D),
        c.dark ? const Color(0xFF16301F) : StockpileColors.successBg,
      ),
      OrderTone.stopped => (c.muted, c.soft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        order.memberLabel,
        style: StockpileFonts.satoshi(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

/// Five short bars: done, the current one, still to come.
class OrderProgressBars extends StatelessWidget {
  final DeliveryOrder order;
  const OrderProgressBars(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    final step = order.progressStep ?? -1;
    return Semantics(
      label: step < 0
          ? 'Cancelled'
          : step >= 5
          ? 'Completed'
          : 'Step ${step + 1} of 5, ${order.progressLabels[step]}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i < step
                        ? c.text
                        : i == step
                        ? c.accent
                        : c.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The labelled progress on an order's own screen.
class OrderProgressSteps extends StatelessWidget {
  final DeliveryOrder order;
  const OrderProgressSteps(this.order, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    final step = order.progressStep ?? -1;
    final labels = order.progressLabels;
    return Semantics(
      label: step < 0
          ? 'Cancelled'
          : step >= 5
          ? 'Completed'
          : 'Step ${step + 1} of 5, ${labels[step]}',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i < step
                            ? c.text
                            : i == step
                            ? c.accent
                            : c.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StockpileFonts.satoshi(
                        fontSize: 11,
                        fontWeight: i == step
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: i <= step ? c.text : c.muted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A white card with the shop's border and radius.
class ShopCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;

  const ShopCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: borderColor ?? c.line),
    );
    return Material(
      color: c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
    );
  }
}

/// An icon and a line of text, for one fact about an order.
class OrderFact extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const OrderFact(this.icon, this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color ?? c.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: StockpileFonts.satoshi(
              fontSize: 13,
              height: 1.45,
              color: color ?? c.muted,
            ),
          ),
        ),
      ],
    );
  }
}

/// A tracking or payment detail with a copy button.
class CopyableLine extends StatelessWidget {
  final String text;
  final String copiedToast;
  final double fontSize;
  const CopyableLine(
    this.text, {
    super.key,
    this.copiedToast = 'Copied',
    this.fontSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    final c = ShopColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: c.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: StockpileFonts.satoshi(
                fontSize: fontSize,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              BotToast.showText(text: copiedToast);
            },
          ),
        ],
      ),
    );
  }
}

// ─── What a member can do to an order ───────────────────────────────────────

/// Every member action on an order, each returning whether something
/// changed. Errors are shown as the database phrased them where it wrote a
/// sentence for people.
class MemberOrderActions {
  MemberOrderActions._();

  static String _say(Object e, String fallback) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message.trim();
    }
    return fallback;
  }

  static String _money(BuildContext context, num? v) =>
      formatMoney(v, symbol: context.read<ConfigService>().currencySymbol);

  static Future<bool> agree(BuildContext context, DeliveryOrder order) async {
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'agree',
      );
      BotToast.showText(text: 'Agreed. Now choose how to pay.');
      return true;
    } catch (e) {
      BotToast.showText(text: _say(e, 'Could not agree. Please try again.'));
      return false;
    }
  }

  /// Offer a different delivery fee: the only part a member can change.
  static Future<bool> counter(BuildContext context, DeliveryOrder order) async {
    final current = order.deliveryFee ?? 0;
    final controller = TextEditingController(
      text: current == current.roundToDouble()
          ? current.round().toString()
          : '$current',
    );
    final currency = context.read<ConfigService>().currencySymbol;
    final fee = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          order.isCourier
              ? 'Offer a different shipping fee'
              : 'Offer a different delivery fee',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item prices are set by the store. The cashier can accept your '
              'offer or reply with another.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Your offer',
                prefixText: '$currency ',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(
                controller.text.trim().replaceAll(',', ''),
              );
              if (v == null || v < 0) {
                BotToast.showText(text: 'Enter an amount of 0 or more.');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Send offer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (fee == null) return false;
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'counter',
        counterFee: fee,
      );
      BotToast.showText(text: 'Offer sent. The cashier will reply.');
      return true;
    } catch (e) {
      BotToast.showText(text: _say(e, 'Could not send the offer.'));
      return false;
    }
  }

  static Future<bool> pay(BuildContext context, DeliveryOrder order) =>
      showOrderPaymentSheet(
        context,
        order: order,
        currencySymbol: context.read<ConfigService>().currencySymbol,
      );

  /// "I have it": Delivered or Shipped → Completed, recorded as member_tap.
  static Future<bool> confirmReceived(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    try {
      await repository.memberConfirmReceived(order.id);
      BotToast.showText(text: 'Thanks, your order is complete.');
      return true;
    } catch (e) {
      BotToast.showText(text: _say(e, 'Could not confirm. Please try again.'));
      return false;
    }
  }

  /// Outside payment (v61): the member says they sent it, with the
  /// reference number if they have one.
  static Future<bool> markSent(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sent your payment?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The store checks it arrived, then sends your order. The '
              'reference number helps them find it.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Reference number (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("I've sent it"),
          ),
        ],
      ),
    );
    final reference = controller.text.trim();
    controller.dispose();
    if (ok != true) return false;
    final error = await repository.memberMarkPaymentSent(
      orderId: order.id,
      reference: reference.isEmpty ? null : reference,
    );
    if (error != null) {
      BotToast.showText(text: error, duration: const Duration(seconds: 6));
      return false;
    }
    BotToast.showText(text: 'The store was told. They will confirm it soon.');
    return true;
  }

  /// Cancel with an optional reason, like the store's and the rider's.
  static Future<bool> cancel(BuildContext context, DeliveryOrder order) async {
    final total = _money(context, order.finalTotal);
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order.isFunds && order.isPaid
                  ? 'Your $total goes back to your funds.'
                  : order.isOutside && order.isPaid
                  ? 'You paid outside the app, so the store refunds you the same way.'
                  : order.isAssigned
                  ? 'The rider assigned to it will see it cancelled.'
                  : 'The store will see it cancelled.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: StockpileColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    final why = reason.text.trim();
    reason.dispose();
    if (ok != true) return false;
    try {
      if (why.isEmpty) {
        await repository.cancelDeliveryOrder(order.id);
      } else {
        await repository.cancelDeliveryOrderWithReason(
          orderId: order.id,
          reason: why,
        );
      }
      BotToast.showText(text: 'Order cancelled.');
      return true;
    } catch (e) {
      BotToast.showText(
        text: _say(e, 'Could not cancel. Please try again.'),
        duration: const Duration(seconds: 5),
      );
      return false;
    }
  }
}

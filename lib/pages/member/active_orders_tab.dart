// lib/pages/member/active_orders_tab.dart
// Member "Active Orders" — shows cashier-assigned item prices, the items
// total, and the proposed delivery fee. The member may Agree (lock the
// final total and route to the POS) or Counter the delivery fee (the ONLY
// negotiable component). Realtime-refreshed.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney, formatRelativeDate;

class ActiveOrdersTab extends StatefulWidget {
  final Member member;

  const ActiveOrdersTab({super.key, required this.member});

  @override
  State<ActiveOrdersTab> createState() => _ActiveOrdersTabState();
}

class _ActiveOrdersTabState extends State<ActiveOrdersTab> {
  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<String>? _sub;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = repository.changes.listen((event) {
      if (event.startsWith('order_') || event == 'orders_changed') _load();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final memberId = widget.member.id;
    if (memberId == null) return;
    try {
      final orders = await repository.fetchDeliveryOrders(memberId: memberId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load your orders.';
        _loading = false;
      });
    }
  }

  Future<void> _agree(DeliveryOrder order) async {
    setState(() => _busy = order.id);
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'agree',
      );
      if (!mounted) return;
      BotToast.showText(text: 'Order agreed — routing to the cashier.');
      await _load();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not agree. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _counter(DeliveryOrder order) async {
    final fee = await _showCounterDialog(order.deliveryFee ?? 0);
    if (fee == null) return;
    setState(() => _busy = order.id);
    try {
      await repository.memberRespondDeliveryOrder(
        orderId: order.id,
        action: 'counter',
        counterFee: fee,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Counter-offer sent.');
      await _load();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the counter-offer.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<double?> _showCounterDialog(double currentFee) async {
    final controller = TextEditingController(
      text: currentFee == currentFee.roundToDouble()
          ? currentFee.round().toString()
          : currentFee.toString(),
    );
    final currency = context.read<ConfigService>().currencySymbol;
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter Delivery Fee'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Proposed delivery fee',
            prefixText: '$currency ',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final fee = double.tryParse(controller.text.trim());
              if (fee == null || fee < 0) {
                BotToast.showText(text: 'Enter a valid delivery fee.');
                return;
              }
              Navigator.pop(ctx, fee);
            },
            child: const Text('Send Counter'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              size: 48,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            const Text('No orders yet.'),
            const SizedBox(height: 4),
            const Text('Browse the Marketplace to place your first order.'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _orders.length,
      itemBuilder: (context, i) => _buildOrderCard(_orders[i]),
    );
  }

  Widget _buildOrderCard(DeliveryOrder order) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark
        ? StockpileColors.darkSurface
        : StockpileColors.surface;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;
    final currency = context.watch<ConfigService>().currencySymbol;
    final busy = _busy == order.id;

    return Card(
      elevation: 0,
      color: surface,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? StockpileColors.darkDivider : StockpileColors.divider,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Order · ${formatRelativeDate(order.createdAt)}',
                    style: StockpileFonts.satoshi(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text,
                    ),
                  ),
                ),
                _StatusBadge(status: order.status),
              ],
            ),
            if ((order.deliveryAddress ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined, size: 16, color: muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!,
                      style: StockpileFonts.satoshi(fontSize: 13, color: muted),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${item.productName ?? 'Item'} × ${item.quantity}',
                        style: StockpileFonts.satoshi(
                          fontSize: 14,
                          color: text,
                        ),
                      ),
                    ),
                    Text(
                      item.unitPrice == null
                          ? '—'
                          : formatMoney(
                              (item.unitPrice! * item.quantity),
                              symbol: currency,
                            ),
                      style: StockpileFonts.satoshi(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: text,
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _totalsRow(
              'Items total',
              formatMoney(order.itemsTotal, symbol: currency),
              text,
            ),
            const SizedBox(height: 6),
            _totalsRow(
              'Delivery fee',
              formatMoney(order.deliveryFee, symbol: currency),
              order.deliveryFee == null ? muted : text,
            ),
            if (order.finalTotal != null) ...[
              const SizedBox(height: 6),
              _totalsRow(
                'Final total',
                formatMoney(order.finalTotal, symbol: currency),
                StockpileColors.primary900,
                bold: true,
              ),
            ],
            if (order.status == DeliveryOrderStatus.cashierPricing) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : () => _counter(order),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text('Counter Delivery Fee'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : () => _agree(order),
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Agree'),
                    ),
                  ),
                ],
              ),
            ] else if (order.status == DeliveryOrderStatus.orderPlaced) ...[
              const SizedBox(height: 12),
              Text(
                'Waiting for the cashier to price your items…',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ] else if (order.status ==
                DeliveryOrderStatus.memberNegotiating) ...[
              const SizedBox(height: 12),
              Text(
                'Counter-offer sent — waiting for the cashier…',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _totalsRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: StockpileFonts.satoshi(fontSize: 14, color: color)),
        Text(
          value,
          style: StockpileFonts.satoshi(
            fontSize: 14,
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg) = switch (status) {
      DeliveryOrderStatus.agreed => (
        StockpileColors.success,
        StockpileColors.successBg,
      ),
      DeliveryOrderStatus.completed => (
        StockpileColors.success,
        StockpileColors.successBg,
      ),
      DeliveryOrderStatus.cancelled => (
        StockpileColors.danger,
        StockpileColors.dangerBg,
      ),
      DeliveryOrderStatus.memberNegotiating => (
        StockpileColors.secondary500,
        StockpileColors.secondary500.withAlpha(30),
      ),
      _ => (
        StockpileColors.primary900,
        StockpileColors.primary900.withAlpha(25),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: StockpileFonts.satoshi(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

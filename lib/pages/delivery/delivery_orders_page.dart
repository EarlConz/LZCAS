// lib/pages/delivery/delivery_orders_page.dart
// Cashier / Admin "Delivery Orders" module (Branch Cashiers are excluded).
//
//   * 'Order Placed'           → assign item prices (Step A) + delivery fee
//                                (Step B), then "Send Quote".
//   * 'Member Negotiating'     → accept the counter, or repropose a fee.
//   * 'Agreed'                 → complete the sale (record in POS + print the
//                                receipt) and mark Completed.
//
// Realtime-refreshed via `repository.changes`.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bot_toast/bot_toast.dart';
import '../../auth/auth.dart';
import '../../db/db.dart';
import '../../services/config_service.dart';
import '../../theme.dart';
import '../../utils/fonts.dart';
import '../../utils/formatters.dart' show formatMoney, formatRelativeDate;
import '../../dialogs/delivery_order_receipt_dialog.dart';

class DeliveryOrdersPage extends StatefulWidget {
  const DeliveryOrdersPage({super.key});

  @override
  State<DeliveryOrdersPage> createState() => _DeliveryOrdersPageState();
}

enum _Filter {
  action('Needs Action'),
  awaiting('Awaiting Member'),
  agreed('Agreed'),
  completed('Completed'),
  cancelled('Cancelled'),
  all('All');

  const _Filter(this.label);
  final String label;
}

class _DeliveryOrdersPageState extends State<DeliveryOrdersPage> {
  List<DeliveryOrder> _orders = [];
  bool _loading = true;
  String? _error;
  StreamSubscription<String>? _sub;
  _Filter _filter = _Filter.action;
  String? _busyOrderId;

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
    try {
      final orders = await repository.fetchDeliveryOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load delivery orders.';
        _loading = false;
      });
    }
  }

  List<DeliveryOrder> get _visible {
    return switch (_filter) {
      _Filter.action =>
        _orders
            .where(
              (o) =>
                  o.status == DeliveryOrderStatus.orderPlaced ||
                  o.status == DeliveryOrderStatus.memberNegotiating,
            )
            .toList(),
      _Filter.awaiting =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.cashierPricing)
            .toList(),
      _Filter.agreed =>
        _orders.where((o) => o.status == DeliveryOrderStatus.agreed).toList(),
      _Filter.completed =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.completed)
            .toList(),
      _Filter.cancelled =>
        _orders
            .where((o) => o.status == DeliveryOrderStatus.cancelled)
            .toList(),
      _Filter.all => _orders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark
        ? StockpileColors.darkTextPrimary
        : StockpileColors.darkText;
    final muted = isDark
        ? StockpileColors.darkTextMuted
        : StockpileColors.mutedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivery Orders',
                style: StockpileFonts.satoshi(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Price member orders and negotiate the delivery fee. '
                'Item prices are final once quoted.',
                style: StockpileFonts.satoshi(fontSize: 13, color: muted),
              ),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              for (final f in _Filter.values) ...[
                ChoiceChip(
                  label: Text(f.label),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
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
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('No orders in this view.'),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      itemCount: visible.length,
      itemBuilder: (context, i) {
        final order = visible[i];
        return _OrderCard(
          order: order,
          busy: _busyOrderId == order.id,
          onBusyChanged: (b) =>
              setState(() => _busyOrderId = b ? order.id : null),
          onChanged: _load,
        );
      },
    );
  }
}

class _OrderCard extends StatefulWidget {
  final DeliveryOrder order;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onChanged;

  const _OrderCard({
    required this.order,
    required this.busy,
    required this.onBusyChanged,
    required this.onChanged,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  late final Map<int, TextEditingController> _priceCtrls;
  late final TextEditingController _deliveryCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrls = {
      for (final it in widget.order.items)
        it.productId: TextEditingController(
          text: it.unitPrice == null
              ? ''
              : it.unitPrice == it.unitPrice!.roundToDouble()
              ? it.unitPrice!.round().toString()
              : it.unitPrice.toString(),
        ),
    };
    final fee = widget.order.deliveryFee;
    _deliveryCtrl = TextEditingController(
      text: fee == null
          ? ''
          : fee == fee.roundToDouble()
          ? fee.round().toString()
          : fee.toString(),
    );
  }

  @override
  void dispose() {
    for (final c in _priceCtrls.values) {
      c.dispose();
    }
    _deliveryCtrl.dispose();
    super.dispose();
  }

  String get _currency => context.read<ConfigService>().currencySymbol;

  Future<void> _sendQuote() async {
    final lines = <Map<String, dynamic>>[];
    var itemsTotal = 0.0;
    for (final item in widget.order.items) {
      final raw = _priceCtrls[item.productId]?.text.trim() ?? '';
      final price = double.tryParse(raw);
      if (price == null || price < 0) {
        BotToast.showText(
          text: 'Enter a valid price for ${item.productName ?? 'every item'}.',
        );
        return;
      }
      final subtotal = price * item.quantity;
      itemsTotal += subtotal;
      lines.add({
        'product_id': item.productId,
        'unit_price': price,
        'subtotal': subtotal,
      });
    }
    final fee = double.tryParse(_deliveryCtrl.text.trim());
    if (fee == null || fee < 0) {
      BotToast.showText(text: 'Enter a valid delivery fee.');
      return;
    }
    final auth = context.read<AuthState>();
    final cashierId = auth.userId;
    if (cashierId == null) return;

    widget.onBusyChanged(true);
    try {
      await repository.sendDeliveryQuote(
        orderId: widget.order.id,
        cashierId: cashierId,
        itemsTotal: itemsTotal,
        deliveryFee: fee,
        lines: lines,
      );
      if (!mounted) return;
      BotToast.showText(text: 'Quote sent to the member.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the quote.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _acceptCounter() async {
    widget.onBusyChanged(true);
    try {
      await repository.cashierResolveDeliveryOrder(
        orderId: widget.order.id,
        action: 'accept',
      );
      if (!mounted) return;
      BotToast.showText(text: 'Counter accepted — order agreed.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not accept the counter.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _repropose() async {
    final fee = await _promptFee('Propose a new delivery fee');
    if (fee == null) return;
    widget.onBusyChanged(true);
    try {
      await repository.cashierResolveDeliveryOrder(
        orderId: widget.order.id,
        action: 'repropose',
        newFee: fee,
      );
      if (!mounted) return;
      BotToast.showText(text: 'New fee proposed to the member.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not send the new fee.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _completeSale() async {
    widget.onBusyChanged(true);
    try {
      // Inject the agreed order into the POS: record each line as a sale and
      // decrement central stock (skipping items that no longer exist).
      final items = await repository.fetchItems();
      final byId = {for (final i in items) i.id!: i};
      final ts = DateTime.now();
      for (final line in widget.order.items) {
        final dbItem = byId[line.productId];
        if (dbItem != null) {
          final newStock = (dbItem.stock - line.quantity).clamp(0, 1 << 30);
          await repository.updateItem(
            dbItem.copyWith(
              stock: newStock,
              lastUpdated: DateTime.now(),
              status: statusFromStock(newStock),
            ),
          );
        }
        await repository.addSale(
          itemId: line.productId,
          itemName: line.productName ?? 'Item',
          quantity: line.quantity,
          price: (line.unitPrice ?? 0).round(),
          timestamp: ts,
          buyerId: widget.order.memberId,
          buyerName: widget.order.memberName,
        );
      }
      await repository.completeDeliveryOrder(widget.order.id);
      if (!mounted) return;
      await DeliveryOrderReceiptDialog(
        order: widget.order,
        currencySymbol: _currency,
      ).show(context);
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not complete the sale.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<void> _cancel() async {
    widget.onBusyChanged(true);
    try {
      await repository.cancelDeliveryOrder(widget.order.id);
      if (!mounted) return;
      BotToast.showText(text: 'Order cancelled.');
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      BotToast.showText(text: 'Could not cancel the order.');
    } finally {
      if (mounted) widget.onBusyChanged(false);
    }
  }

  Future<double?> _promptFee(String title) async {
    final ctrl = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Delivery fee',
            prefixText: '$_currency ',
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
              final fee = double.tryParse(ctrl.text.trim());
              if (fee == null || fee < 0) {
                BotToast.showText(text: 'Enter a valid delivery fee.');
                return;
              }
              Navigator.pop(ctx, fee);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
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
    final order = widget.order;
    final currency = _currency;
    final status = order.status;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.memberName ?? 'Member order',
                        style: StockpileFonts.satoshi(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      Text(
                        '${formatRelativeDate(order.createdAt)} · '
                        '${order.items.length} line${order.items.length == 1 ? '' : 's'}',
                        style: StockpileFonts.satoshi(
                          fontSize: 12,
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: status),
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
            if (status == DeliveryOrderStatus.orderPlaced)
              _buildQuoteEditor(text, muted)
            else
              _buildItemizedLines(text, muted),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildTotals(text, currency),
            const SizedBox(height: 16),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildQuoteEditor(Color text, Color muted) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Assign item prices (fixed once sent)',
          style: StockpileFonts.satoshi(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: muted,
          ),
        ),
        const SizedBox(height: 8),
        for (final item in widget.order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? 'Item'} × ${item.quantity}',
                    style: StockpileFonts.satoshi(fontSize: 14, color: text),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _priceCtrls[item.productId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixText: '$_currency ',
                      hintText: 'Unit price',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                'Delivery fee',
                style: StockpileFonts.satoshi(fontSize: 14, color: text),
              ),
            ),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _deliveryCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  prefixText: '$_currency ',
                  hintText: 'Fee',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemizedLines(Color text, Color muted) {
    return Column(
      children: [
        for (final item in widget.order.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.productName ?? 'Item'} × ${item.quantity}',
                    style: StockpileFonts.satoshi(fontSize: 14, color: text),
                  ),
                ),
                Text(
                  item.unitPrice == null
                      ? '—'
                      : formatMoney(
                          (item.unitPrice! * item.quantity),
                          symbol: _currency,
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
      ],
    );
  }

  Widget _buildTotals(Color text, String currency) {
    final order = widget.order;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Items total',
              style: StockpileFonts.satoshi(fontSize: 14, color: text),
            ),
            Text(
              formatMoney(order.itemsTotal, symbol: currency),
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Delivery fee',
              style: StockpileFonts.satoshi(fontSize: 14, color: text),
            ),
            Text(
              formatMoney(order.deliveryFee, symbol: currency),
              style: StockpileFonts.satoshi(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: order.deliveryFee == null
                    ? text
                    : StockpileColors.primary900,
              ),
            ),
          ],
        ),
        if (order.finalTotal != null) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Final total',
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: text,
                ),
              ),
              Text(
                formatMoney(order.finalTotal, symbol: currency),
                style: StockpileFonts.satoshi(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: StockpileColors.primary900,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    final status = widget.order.status;
    final busy = widget.busy;

    switch (status) {
      case DeliveryOrderStatus.orderPlaced:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : _sendQuote,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Send Quote'),
            ),
            TextButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel Order'),
            ),
          ],
        );
      case DeliveryOrderStatus.memberNegotiating:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : _repropose,
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Propose New Fee'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : _acceptCounter,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Accept Counter'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: busy ? null : _cancel,
              child: const Text('Cancel Order'),
            ),
          ],
        );
      case DeliveryOrderStatus.cashierPricing:
        return Text(
          'Waiting for the member to review the quote…',
          style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
        );
      case DeliveryOrderStatus.agreed:
        return SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: busy ? null : _completeSale,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('Complete Sale & Print Receipt'),
          ),
        );
      case DeliveryOrderStatus.completed:
      case DeliveryOrderStatus.cancelled:
        return Text(
          status == DeliveryOrderStatus.completed
              ? 'Order completed.'
              : 'Order cancelled.',
          style: StockpileFonts.satoshi(fontSize: 13, color: Colors.grey),
        );
      default:
        return const SizedBox.shrink();
    }
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
      DeliveryOrderStatus.cashierPricing => (
        StockpileColors.primary900,
        StockpileColors.primary900.withAlpha(25),
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
